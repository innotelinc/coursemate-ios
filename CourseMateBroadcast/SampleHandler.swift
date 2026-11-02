//
//  SampleHandler.swift
//  CourseMate broadcast extension
//
//  ReplayKit calls this on a private serial queue. Nothing here may block that
//  queue — a slow upload shows up as a stuttering broadcast — so uploads are
//  detached Tasks capped at two in flight, and newer frames are dropped rather
//  than queued.
//
//  The session is re-read from the App Group control file while broadcasting,
//  so switching course in the app takes effect on the next frame instead of
//  requiring the broadcast to be stopped and restarted.
//
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private var settings = CMSettings.load()
    private let sampler = FrameSampler()
    private let audio = AudioChunker()
    private let control = ControlWatcher()
    private let status = StatusBox()

    private let lock = NSLock()

    // Frames and audio never share a slot. An audio chunk waits on a server-side
    // transcription that can take tens of seconds, and while it held one of two
    // shared slots the frames queued behind it — which is how the desk went quiet
    // while the extension reported "audio: the request timed out". One audio
    // chunk in flight is enough: a second 12-second window would only wait behind
    // the first one.
    private var framesInFlight = 0
    private var audioInFlight = 0
    private let maxFramesInFlight = 2

    /// Set when the server answers 404 for this session id. Sending stops for the
    /// rest of the broadcast — re-posting into a session the server has forgotten
    /// is exactly the "posting to the wrong session" failure this prevents — until
    /// the app hands over a new id in the control file.
    private var sessionRefused = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        settings = CMSettings.load()
        sampler.reset()
        audio.reset()
        status.setSession(settings.sessionID, course: settings.course)

        if settings.sessionID.isEmpty {
            NSLog("CourseMate: no session yet; open the console in the app — the extension starts sending as soon as one exists.")
        }
        if settings.server.isEmpty {
            NSLog("CourseMate: no server URL configured.")
        }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        followControlFile()
        guard !settings.sessionID.isEmpty, isSending else { return }

        switch sampleBufferType {
        case .video:
            guard let frame = sampler.jpeg(from: sampleBuffer) else { return }
            send(path: "/api/ingest/frame", payload: [
                "session_id": settings.sessionID,
                "image_b64": frame.data.base64EncodedString(),
                "mime": "image/jpeg",
                "hash": String(frame.hash, radix: 16),
            ], kind: "frame")

        case .audioApp, .audioMic:
            guard let wav = audio.append(sampleBuffer) else { return }
            send(path: "/api/ingest/audio", payload: [
                "session_id": settings.sessionID,
                "audio_b64": wav.base64EncodedString(),
                "mime": "audio/wav",
            ], kind: "audio")

        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        if isSending, !settings.sessionID.isEmpty, let wav = audio.flush() {
            send(path: "/api/ingest/audio", payload: [
                "session_id": settings.sessionID,
                "audio_b64": wav.base64EncodedString(),
                "mime": "audio/wav",
            ], kind: "audio")
        }
        status.flush(force: true)
    }

    // MARK: - Live session switching

    /// Cheap (throttled stat) on every sample buffer; only re-reads and resets
    /// when the app actually rewrote the control file.
    private func followControlFile() {
        let (payload, changed) = control.refresh()
        guard changed, let payload else { return }

        let next = CMSettings(
            server: payload.server,
            token: payload.token,
            sessionID: payload.session,
            course: payload.course
        )

        if next.sessionID != settings.sessionID {
            NSLog("CourseMate: session switched to \(next.sessionID.isEmpty ? "(none)" : next.sessionID)")
            // Buffered audio and the last-frame hash belong to the old session.
            audio.reset()
            sampler.reset()
            // A fresh id deserves a try even if the previous one was refused.
            lock.lock()
            sessionRefused = false
            lock.unlock()
        }
        settings = next
        status.setSession(next.sessionID, course: next.course)
        status.flush(force: true)
    }

    // MARK: - Transport

    private func send(path: String, payload: [String: Any], kind: String) {
        guard reserveSlot(kind) else { return }
        let base = settings.server
        let token = settings.token
        // Captured here, on the ReplayKit queue: the upload Task must not read
        // `settings` while the control watcher may be assigning it.
        let course = settings.course
        // Audio is a background transcription rather than something a frame has
        // to wait on, so it is allowed to take longer than a frame upload.
        let timeout: TimeInterval = kind == "audio" ? 45 : 25

        Task {
            defer { releaseSlot(kind) }
            do {
                _ = try await CourseMateAPI.post(
                    base: base,
                    token: token,
                    path: path,
                    payload: payload,
                    timeout: timeout
                )
                if kind == "frame" { status.recordFrame() } else { status.recordAudio() }
            } catch {
                if refuseIfSessionUnknown(error, kind: kind, course: course) { return }
                status.recordError("\(kind): \(error.localizedDescription)")
                NSLog("CourseMate: \(path) failed: \(error.localizedDescription)")
            }
        }
    }

    /// A 404 on an ingest path means the server no longer has this session. Stop
    /// instead of retrying: every later upload would land in a session nobody is
    /// watching. Only counters are touched here — the sample buffers belong to the
    /// ReplayKit queue and are reset on the next control-file change.
    private func refuseIfSessionUnknown(_ error: Error, kind: String, course: String) -> Bool {
        guard let api = error as? APIError, case .status(404, _) = api else { return false }

        lock.lock()
        let first = !sessionRefused
        sessionRefused = true
        lock.unlock()

        guard first else { return true }
        status.setSession("", course: course)
        status.recordError("The session ended — open the console for a new one.")
        NSLog("CourseMate: \(kind) refused with 404; stopping until a new session is opened.")
        return true
    }

    /// Read under the same lock that sets it, so the sample queue never sees a
    /// torn or stale value.
    private var isSending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !sessionRefused
    }

    private func reserveSlot(_ kind: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if kind == "audio" {
            guard audioInFlight == 0 else { return false }
            audioInFlight = 1
            return true
        }
        guard framesInFlight < maxFramesInFlight else { return false }
        framesInFlight += 1
        return true
    }

    private func releaseSlot(_ kind: String) {
        lock.lock()
        if kind == "audio" {
            audioInFlight = 0
        } else {
            framesInFlight = max(0, framesInFlight - 1)
        }
        lock.unlock()
    }
}
