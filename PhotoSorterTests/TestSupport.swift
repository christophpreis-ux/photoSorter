import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@testable import PhotoSorter

/// Hilfsfunktionen, um Testfotos und Analyse-Ergebnisse zu erzeugen – ohne echte (private) Fotos.
enum TestSupport {
    static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoSorterTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func touch(_ url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data("test".utf8))
    }

    /// Schachbrettmuster – optional weichgezeichnet, um Unschärfe zu simulieren.
    static func writeJPEG(to url: URL, width: Int = 800, height: Int = 600, blurRadius: Double = 0) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let tile = 20
        for y in stride(from: 0, to: height, by: tile) {
            for x in stride(from: 0, to: width, by: tile) {
                let dark = ((x / tile) + (y / tile)) % 2 == 0
                context.setFillColor(dark ? CGColor(gray: 0.1, alpha: 1) : CGColor(gray: 0.9, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: tile, height: tile))
            }
        }
        var image = context.makeImage()!
        if blurRadius > 0 {
            let ci = CIImage(cgImage: image).clampedToExtent()
                .applyingGaussianBlur(sigma: blurRadius)
                .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            image = CIContext().createCGImage(ci, from: ci.extent)!
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    static func face(x: CGFloat, y: CGFloat = 0.5, size: CGFloat = 0.12, eyes: Double = 0.32,
                     quality: Float = 0.5, sharpness: Double = 300, yaw: Double = 0) -> FaceInfo {
        FaceInfo(boundingBox: CGRect(x: x, y: y, width: size, height: size), captureQuality: quality,
                 leftEyeAspect: eyes, rightEyeAspect: eyes, yaw: yaw, sharpness: sharpness)
    }

    static func analysis(faces: [FaceInfo] = [], sharpness: Double = 500, labels: [String: Float] = [:],
                         aesthetics: Float = 0.3, isUtility: Bool = false) -> PhotoAnalysis {
        let category: PhotoCategory = faces.count >= 2 ? .group : faces.count == 1 ? .portrait : .other
        return PhotoAnalysis(featurePrint: nil, faces: faces, peakSharpness: sharpness, globalSharpness: sharpness,
                             meanLuma: 0.5, highlightClipping: 0, shadowClipping: 0, aesthetics: aesthetics,
                             isUtility: isUtility, hasAnimal: false, labels: labels, category: category,
                             thumbnailData: nil, pixelSize: CGSize(width: 4000, height: 3000))
    }

    static func photo(_ name: String, at seconds: TimeInterval, analysis: PhotoAnalysis?, favorite: Bool = false) -> PhotoItem {
        let url = URL(fileURLWithPath: "/tmp/\(name).jpg")
        let item = PhotoItem(baseName: name, files: [url], primaryURL: url, captureDate: baseDate + seconds)
        item.analysis = analysis
        item.isFavorite = favorite
        return item
    }

    static func scene(_ photos: [PhotoItem], index: Int = 1) -> PhotoScene {
        PhotoScene(index: index, photos: photos)
    }
}
