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
    private var inFlight = 0
    private let maxInFlight = 2

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        settings = CMSettings.load()
        sampler.reset()
        audio.reset()
        status.setSession(settings.sessionID, course: settings.course)

        if settings.sessionID.isEmpty {
            NSLog("CourseMate: no session yet; the extension will start sending as soon as one is created.")
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
        guard !settings.sessionID.isEmpty else { return }

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
        if let wav = audio.flush() {
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
        }
        settings = next
        status.setSession(next.sessionID, course: next.course)
        status.flush(force: true)
    }

    // MARK: - Transport

    private func send(path: String, payload: [String: Any], kind: String) {
        guard reserveSlot() else { return }
        let base = settings.server
        let token = settings.token

        Task {
            defer { releaseSlot() }
            do {
                _ = try await CourseMateAPI.post(
                    base: base,
                    token: token,
                    path: path,
                    payload: payload,
                    timeout: 25
                )
                if kind == "frame" { status.recordFrame() } else { status.recordAudio() }
            } catch {
                status.recordError("\(kind): \(error.localizedDescription)")
                NSLog("CourseMate: \(path) failed: \(error.localizedDescription)")
            }
        }
    }

    private func reserveSlot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard inFlight < maxInFlight else { return false }
        inFlight += 1
        return true
    }

    private func releaseSlot() {
        lock.lock()
        inFlight -= 1
        lock.unlock()
    }
}
