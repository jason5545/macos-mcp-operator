import AppKit
import CoreGraphics
import CoreTypes
import Foundation
import ImageIO

public final class SystemCaptureAdapter: CaptureAdapting, @unchecked Sendable {
    public init() {}

    public func capture(region: CaptureRegion?, quality: Double?) async throws -> CaptureResult {
        let baseImage: CGImage
        let usedCoreGraphicsCapture: Bool
        if let image = CGDisplayCreateImage(CGMainDisplayID()) {
            baseImage = image
            usedCoreGraphicsCapture = true
        } else {
            baseImage = try captureUsingScreencapture(region: region)
            usedCoreGraphicsCapture = false
        }

        let cropped: CGImage
        if let region, usedCoreGraphicsCapture {
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height).integral
            cropped = baseImage.cropping(to: rect) ?? baseImage
        } else {
            cropped = baseImage
        }

        // CoreGraphics capture is in physical pixels on Retina displays.
        // screencapture output is already in logical pixels, so only downscale CoreGraphics output.
        let image: CGImage
        let screenScale = usedCoreGraphicsCapture ? (NSScreen.main?.backingScaleFactor ?? 1.0) : 1.0
        if usedCoreGraphicsCapture, screenScale > 1.0 {
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

    private func captureUsingScreencapture(region: CaptureRegion?) throws -> CGImage {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent("macos-mcp-operator-images", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let outputURL = temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        defer {
            try? fileManager.removeItem(at: outputURL)
        }

        var arguments = ["-x", "-t", "png"]
        if let region {
            let rect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height).integral
            arguments.append("-R")
            arguments.append("\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.size.width)),\(Int(rect.size.height))")
        }
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        let standardErrorPipe = Pipe()
        process.standardError = standardErrorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stderrText.isEmpty {
                throw OperatorError("Failed to capture screen")
            }
            throw OperatorError("Failed to capture screen: \(stderrText)")
        }

        let pngData = try Data(contentsOf: outputURL)
        guard
            let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw OperatorError("Failed to decode screencapture output")
        }

        return image
    }
}
