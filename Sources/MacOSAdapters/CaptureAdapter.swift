import AppKit
import CoreGraphics
import CoreTypes
import Foundation

public final class SystemCaptureAdapter: CaptureAdapting, @unchecked Sendable {
    public init() {}

    public func capture(region: CaptureRegion?, quality: Double?) async throws -> CaptureResult {
        guard let fullImage = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw OperatorError("Failed to capture screen")
        }

        let cropped: CGImage
        if let region {
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height).integral
            cropped = fullImage.cropping(to: rect) ?? fullImage
        } else {
            cropped = fullImage
        }

        // Downscale Retina captures to 1x logical resolution
        let image: CGImage
        let screenScale = NSScreen.main?.backingScaleFactor ?? 1.0
        if screenScale > 1.0 {
            let logicalW = Int(Double(cropped.width) / screenScale)
            let logicalH = Int(Double(cropped.height) / screenScale)
            if let ctx = CGContext(
                data: nil,
                width: logicalW,
                height: logicalH,
                bitsPerComponent: cropped.bitsPerComponent,
                bytesPerRow: 0,
                space: cropped.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: cropped.bitmapInfo.rawValue
            ) {
                ctx.interpolationQuality = .high
                ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: logicalW, height: logicalH))
                image = ctx.makeImage() ?? cropped
            } else {
                image = cropped
            }
        } else {
            image = cropped
        }

        let rep = NSBitmapImageRep(cgImage: image)

        let imageData: Data
        let format: String
        if let quality {
            let clampedQuality = min(max(quality, 0.0), 1.0)
            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: clampedQuality]) else {
                throw OperatorError("Failed to encode JPEG")
            }
            imageData = jpegData
            format = "jpeg"
        } else {
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                throw OperatorError("Failed to encode PNG")
            }
            imageData = pngData
            format = "png"
        }

        return CaptureResult(
            imageBase64: imageData.base64EncodedString(),
            format: format,
            width: image.width,
            height: image.height
        )
    }
}
