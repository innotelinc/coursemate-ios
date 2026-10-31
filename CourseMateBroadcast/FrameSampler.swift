//
//  FrameSampler.swift
//
//  Every uploaded frame costs one vision call on the server, so this does two
//  jobs before anything leaves the device: throttle by wall clock, and drop a
//  frame whose 8x8 average hash is within a couple of bits of the last one.
//  A static slide therefore costs one call, not one per sample buffer.
//
import CoreImage
import UIKit

final class FrameSampler {
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var lastSentAt = Date.distantPast
    private var lastHash: UInt64 = 0

    private let minInterval: TimeInterval = 2.5
    private let maxWidth: CGFloat = 1280
    private let hashDistance: Int = 2

    func reset() {
        lastSentAt = .distantPast
        lastHash = 0
    }

    func jpeg(from buffer: CMSampleBuffer) -> (data: Data, hash: UInt64)? {
        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= minInterval else { return nil }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return nil }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let width = image.extent.width
        guard width > 0, image.extent.height > 0 else { return nil }

        let scale = min(1, maxWidth / width)
        let scaled = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let hash = Self.averageHash(cgImage)

        if lastHash != 0 {
            let distance = (hash ^ lastHash).nonzeroBitCount
            if distance <= hashDistance { return nil }
        }

        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) else { return nil }
        lastSentAt = now
        lastHash = hash
        return (data, hash)
    }

    /// 8x8 greyscale average hash, packed into 64 bits. Cheap, and good enough
    /// to tell "same slide" from "new question".
    private static func averageHash(_ image: CGImage) -> UInt64 {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let space = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: space,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return 0 }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let average = total / (side * side)
        var hash: UInt64 = 0
        for (index, pixel) in pixels.enumerated() where Int(pixel) > average {
            hash |= 1 << UInt64(index)
        }
        return hash
    }
}
