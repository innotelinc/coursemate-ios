//
//  SampleHandler.swift
//  CourseMate broadcast extension
//
//  ReplayKit calls this on a private serial queue. Nothing here may block that
//  queue — a slow upload shows up as a stuttering broadcast — so uploads are
//  detached Tasks capped at two in flight, and newer frames are dropped rather
//  than queued.
//
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private var settings = CMSettings.load()
    private let sampler = FrameSampler()
    private let audio = AudioChunker()

    private let lock = NSLock()
    private var inFlight = 0
    private let maxInFlight = 2

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        settings = CMSettings.load()
        sampler.reset()
        if settings.sessionID.isEmpty {
            NSLog("CourseMate: no session_id in the App Group; frames will be rejected until one is set.")
        }
        if settings.server.isEmpty {
            NSLog("CourseMate: no server URL configured.")
        }
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard !settings.sessionID.isEmpty else { return }

        switch sampleBufferType {
        case .video:
            guard let frame = sampler.jpeg(from: sampleBuffer) else { return }
            send(path: "/api/ingest/frame", payload: [
                "session_id": settings.sessionID,
                "image_b64": frame.data.base64EncodedString(),
                "mime": "image/jpeg",
                "hash": String(frame.hash, radix: 16),
            ])

        case .audioApp, .audioMic:
            if let wav = audio.append(sampleBuffer) { upload(wav) }

        @unknown default:
            break
        }
    }

    override func broadcastFinished() {
        if let wav = audio.flush() { upload(wav) }
    }

    // MARK: - Transport

    private func upload(_ wav: Data) {
        send(path: "/api/ingest/audio", payload: [
            "session_id": settings.sessionID,
            "audio_b64": wav.base64EncodedString(),
            "mime": "audio/wav",
        ])
    }

    private func send(path: String, payload: [String: Any]) {
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
            } catch {
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
