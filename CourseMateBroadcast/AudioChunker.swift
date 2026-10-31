//
//  AudioChunker.swift
//
//  ReplayKit hands over raw LinearPCM sample buffers, which no speech model
//  accepts. This accumulates them, downmixes to 16-bit mono and wraps the
//  result in a WAV header every ~12 seconds.
//
//  Known limitation: no resampling. The hardware rate (usually 44.1 or 48 kHz)
//  is carried through and declared in the header, which Whisper-derived
//  endpoints handle; the server's ffmpeg path handles the rest.
//
import CoreMedia
import Foundation

final class AudioChunker {
    private var pcm = Data()
    private var sampleRate: Double = 44_100
    private var windowStart = Date()
    private let window: TimeInterval = 12
    private let hardLimitBytes = 12 * 48_000 * 2

    /// Returns a finished WAV when the window closes, otherwise nil.
    func append(_ buffer: CMSampleBuffer) -> Data? {
        guard let description = Self.streamDescription(buffer) else { return nil }
        let asbd = description.pointee
        if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
        guard let mono = Self.mono16(buffer, asbd) else { return nil }

        pcm.append(mono)
        let due = Date().timeIntervalSince(windowStart) >= window || pcm.count >= hardLimitBytes
        guard due else { return nil }
        return drain()
    }

    /// Called from broadcastFinished so the last few seconds are not lost.
    func flush() -> Data? {
        pcm.isEmpty ? nil : drain()
    }

    /// Called when the session changes mid-broadcast: the buffered PCM belongs
    /// to the previous session, so it is dropped rather than attributed to the
    /// new one.
    func reset() {
        pcm.removeAll(keepingCapacity: true)
        windowStart = Date()
    }

    private func drain() -> Data? {
        windowStart = Date()
        let payload = pcm
        pcm.removeAll(keepingCapacity: true)
        guard payload.count >= 3_200 else { return nil } // under ~100 ms of audio
        return Self.wav(payload, sampleRate: sampleRate)
    }

    // MARK: - Format

    private static func streamDescription(
        _ buffer: CMSampleBuffer
    ) -> UnsafePointer<AudioStreamBasicDescription>? {
        guard let format = CMSampleBufferGetFormatDescription(buffer) else { return nil }
        return CMAudioFormatDescriptionGetStreamBasicDescription(format)
    }

    // MARK: - PCM

    private static func mono16(
        _ buffer: CMSampleBuffer,
        _ asbd: AudioStreamBasicDescription
    ) -> Data? {
        guard asbd.mFormatID == kAudioFormatLinearPCM else { return nil }

        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let frames = CMSampleBufferGetNumSamples(buffer)
        guard channels > 0, frames > 0 else { return nil }

        let sampleBytes = isFloat ? 4 : 2
        if isFloat && asbd.mBitsPerChannel != 32 { return nil }
        if !isFloat && asbd.mBitsPerChannel != 16 { return nil }

        var needed = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: &needed,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, needed > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: needed,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)

        var block: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: needed,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var out = [Int16](repeating: 0, count: frames)

        for frame in 0 ..< frames {
            var sum = 0.0
            var counted = 0

            if isNonInterleaved {
                for buffer in buffers {
                    guard let data = buffer.mData else { continue }
                    let offset = frame * sampleBytes
                    guard offset + sampleBytes <= Int(buffer.mDataByteSize) else { continue }
                    sum += sample(data.advanced(by: offset), isFloat: isFloat)
                    counted += 1
                }
            } else if let buffer = buffers.first, let data = buffer.mData {
                let frameBytes = sampleBytes * channels
                let base = frame * frameBytes
                guard base + frameBytes <= Int(buffer.mDataByteSize) else { continue }
                for channel in 0 ..< channels {
                    sum += sample(data.advanced(by: base + channel * sampleBytes), isFloat: isFloat)
                }
                counted = channels
            }

            guard counted > 0 else { continue }
            let mixed = max(-1.0, min(1.0, sum / Double(counted)))
            out[frame] = Int16(mixed * 32_767)
        }

        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func sample(_ pointer: UnsafeRawPointer, isFloat: Bool) -> Double {
        if isFloat {
            return Double(pointer.load(as: Float32.self))
        }
        return Double(pointer.load(as: Int16.self)) / 32_768.0
    }

    // MARK: - WAV

    private static func wav(_ payload: Data, sampleRate: Double) -> Data {
        var data = Data(capacity: payload.count + 44)
        let rate = UInt32(sampleRate.rounded())
        let bytes = UInt32(payload.count)

        func text(_ value: String) { data.append(contentsOf: Array(value.utf8)) }
        func u32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func u16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }

        text("RIFF")
        u32(36 + bytes)
        text("WAVE")
        text("fmt ")
        u32(16)                 // PCM chunk size
        u16(1)                  // PCM
        u16(1)                  // mono
        u32(rate)
        u32(rate * 2)           // byte rate
        u16(2)                  // block align
        u16(16)                 // bits per sample
        text("data")
        u32(bytes)
        data.append(payload)
        return data
    }
}
