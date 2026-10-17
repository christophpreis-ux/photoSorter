import Foundation
import ImageIO
import CoreGraphics
import Vision
import Accelerate
import UniformTypeIdentifiers

struct AnalysisOutput: @unchecked Sendable {
    var analysis: PhotoAnalysis
    var captureDate: Date
}

/// Analysiert ein einzelnes Foto komplett on-device (ImageIO, Vision, Accelerate).
enum ImageAnalyzer {
    static let analysisMaxPixel = 1400
    static let faceDetailMaxPixel = 3000
    static let thumbnailMaxPixel = 420

    static func analyze(url: URL, isRaw: Bool) -> AnalysisOutput? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let date = captureDate(from: props, url: url)
        guard let image = makeImage(source: source, maxPixel: analysisMaxPixel, isRaw: isRaw),
              let gray = GrayImage(image) else { return nil }
        let originalSize = pixelSize(from: props) ?? CGSize(width: image.width, height: image.height)

        // Schärfe & Belichtung
        let laplacian = gray.laplacian()
        let peakSharpness = laplacian.peakVariance(grid: 4)
        let globalSharpness = laplacian.variance(x0: 0, y0: 0, x1: laplacian.width, y1: laplacian.height)
        let luma = gray.lumaStats()

        // Vision: Feature Print (Ähnlichkeit) + Gesichter
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let featureRequest = VNGenerateImageFeaturePrintRequest()
        let faceRequest = VNDetectFaceLandmarksRequest()
        try? handler.perform([featureRequest, faceRequest])

        var aesthetics: Float?
        var isUtility = false
        let aestheticsRequest = VNCalculateImageAestheticsScoresRequest()
        if (try? handler.perform([aestheticsRequest])) != nil, let result = aestheticsRequest.results?.first {
            aesthetics = result.overallScore
            isUtility = result.isUtility
        }

        let animalRequest = VNRecognizeAnimalsRequest()
        try? handler.perform([animalRequest])
        let hasAnimal = animalRequest.results?.contains { $0.confidence > 0.6 } ?? false

        // Kleine Gesichter (Gruppenfotos) in höherer Auflösung erneut auswerten.
        var faceObservations = faceRequest.results ?? []
        var faceHandler = handler
        var faceImageSize = CGSize(width: image.width, height: image.height)
        var faceLaplacian = laplacian
        let hasSmallFaces = faceObservations.contains { $0.boundingBox.width * CGFloat(image.width) < 80 }
        if hasSmallFaces,
           max(originalSize.width, originalSize.height) > CGFloat(analysisMaxPixel) * 1.3,
           let hiRes = makeImage(source: source, maxPixel: faceDetailMaxPixel, isRaw: isRaw),
           let hiGray = GrayImage(hiRes) {
            let hiHandler = VNImageRequestHandler(cgImage: hiRes, options: [:])
            let hiFaces = VNDetectFaceLandmarksRequest()
            if (try? hiHandler.perform([hiFaces])) != nil, let results = hiFaces.results, results.count >= faceObservations.count {
                faceObservations = results
                faceHandler = hiHandler
                faceImageSize = CGSize(width: hiRes.width, height: hiRes.height)
                faceLaplacian = hiGray.laplacian()
            }
        }

        var qualities = [Float?](repeating: nil, count: faceObservations.count)
        if !faceObservations.isEmpty {
            let qualityRequest = VNDetectFaceCaptureQualityRequest()
            qualityRequest.inputFaceObservations = faceObservations
            if (try? faceHandler.perform([qualityRequest])) != nil, let results = qualityRequest.results {
                for result in results {
                    if let index = bestMatch(for: result.boundingBox, in: faceObservations) {
                        qualities[index] = result.faceCaptureQuality
                    }
                }
            }
        }

        var faces: [FaceInfo] = faceObservations.enumerated().map { index, face in
            let eyeRegion = face.boundingBox.insetBy(dx: face.boundingBox.width * 0.15, dy: face.boundingBox.height * 0.2)
            return FaceInfo(
                boundingBox: face.boundingBox,
                captureQuality: qualities[index],
                leftEyeAspect: eyeAspect(face.landmarks?.leftEye, imageSize: faceImageSize),
                rightEyeAspect: eyeAspect(face.landmarks?.rightEye, imageSize: faceImageSize),
                yaw: face.yaw?.doubleValue,
                sharpness: faceLaplacian.variance(normalizedVisionRect: eyeRegion)
            )
        }
        // Hintergrundgesichter ignorieren.
        let maxArea = faces.map(\.area).max() ?? 0
        faces = faces.filter { $0.area >= 0.0004 && $0.area >= maxArea * 0.12 }
            .sorted { $0.boundingBox.midX < $1.boundingBox.midX }

        let category: PhotoCategory
        if faces.count >= 2 {
            category = .group
        } else if let face = faces.first, face.area >= 0.004 {
            category = .portrait
        } else if hasAnimal {
            category = .animal
        } else {
            category = .other
        }

        let analysis = PhotoAnalysis(
            featurePrint: featureRequest.results?.first,
            faces: faces,
            peakSharpness: peakSharpness,
            globalSharpness: globalSharpness,
            meanLuma: luma.mean,
            highlightClipping: luma.highlights,
            shadowClipping: luma.shadows,
            aesthetics: aesthetics,
            isUtility: isUtility,
            hasAnimal: hasAnimal,
            category: category,
            thumbnailData: jpegThumbnail(from: image, maxPixel: thumbnailMaxPixel),
            pixelSize: originalSize
        )
        return AnalysisOutput(analysis: analysis, captureDate: date)
    }

    // MARK: - Laden

    /// Lädt ein verkleinertes Bild. Bei RAWs wird bevorzugt die eingebettete Vorschau genutzt (schnell).
    static func makeImage(source: CGImageSource, maxPixel: Int, isRaw: Bool) -> CGImage? {
        func thumbnail(always: Bool) -> CGImage? {
            let options: [CFString: Any] = [
                always ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        if isRaw {
            if let preview = thumbnail(always: false), max(preview.width, preview.height) >= maxPixel / 2 {
                return preview
            }
        }
        return thumbnail(always: true)
    }

    static func loadImage(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let isRaw = PhotoScanner.rawExtensions.contains(url.pathExtension.lowercased())
        return makeImage(source: source, maxPixel: maxPixel, isRaw: isRaw)
    }

    private static let exifFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    static func captureDate(from props: [CFString: Any], url: URL) -> Date {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let string = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        if let string, var date = exifFormatter.date(from: string) {
            // Sub-Sekunden sind wichtig für Serienbilder.
            if let subsec = exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String, let fraction = Double("0." + subsec) {
                date += fraction
            }
            return date
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate ?? .distantPast
    }

    private static func pixelSize(from props: [CFString: Any]) -> CGSize? {
        guard let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    // MARK: - Gesichter

    private static func eyeAspect(_ region: VNFaceLandmarkRegion2D?, imageSize: CGSize) -> Double? {
        guard let region, region.pointCount >= 6 else { return nil }
        let points = region.pointsInImage(imageSize: imageSize)
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(), maxX - minX > 0 else { return nil }
        return Double((maxY - minY) / (maxX - minX))
    }

    private static func bestMatch(for box: CGRect, in faces: [VNFaceObservation]) -> Int? {
        var best: (Int, CGFloat)?
        for (index, face) in faces.enumerated() {
            let intersection = face.boundingBox.intersection(box)
            guard !intersection.isNull else { continue }
            let union = face.boundingBox.width * face.boundingBox.height + box.width * box.height - intersection.width * intersection.height
            let iou = intersection.width * intersection.height / max(union, 0.000001)
            if iou > (best?.1 ?? 0.3) { best = (index, iou) }
        }
        return best?.0
    }

    // MARK: - Vorschaubild

    static func jpegThumbnail(from image: CGImage, maxPixel: Int) -> Data? {
        let scale = min(1, Double(maxPixel) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, small, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - Bildverarbeitung mit Accelerate

struct GrayImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        guard width > 2, height > 2 else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height)
        let ok = buffer.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(data: pointer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard ok else { return nil }
        pixels = buffer
    }

    func lumaStats() -> (mean: Double, highlights: Double, shadows: Double) {
        var histogram = [vImagePixelCount](repeating: 0, count: 256)
        var pixels = pixels
        pixels.withUnsafeMutableBytes { pointer in
            var buffer = vImage_Buffer(data: pointer.baseAddress, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width)
            histogram.withUnsafeMutableBufferPointer { hist in
                _ = vImageHistogramCalculation_Planar8(&buffer, hist.baseAddress!, vImage_Flags(kvImageNoFlags))
            }
        }
        let total = Double(width * height)
        var weighted = 0.0
        for (value, count) in histogram.enumerated() { weighted += Double(value) * Double(count) }
        let highlights = histogram[250...].reduce(0, +)
        let shadows = histogram[0...5].reduce(0, +)
        return (weighted / total / 255, Double(highlights) / total, Double(shadows) / total)
    }

    func laplacian() -> LaplacianMap {
        var source = [Float](repeating: 0, count: width * height)
        vDSP.convertElements(of: pixels, to: &source)
        var output = [Float](repeating: 0, count: width * height)
        let kernel: [Float] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        source.withUnsafeMutableBytes { src in
            output.withUnsafeMutableBytes { dst in
                var srcBuffer = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height),
                                              width: vImagePixelCount(width), rowBytes: width * 4)
                var dstBuffer = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                              width: vImagePixelCount(width), rowBytes: width * 4)
                _ = vImageConvolve_PlanarF(&srcBuffer, &dstBuffer, nil, 0, 0, kernel, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return LaplacianMap(width: width, height: height, values: output)
    }
}

struct LaplacianMap {
    let width: Int
    let height: Int
    let values: [Float]

    func variance(x0: Int, y0: Int, x1: Int, y1: Int) -> Double {
        let x0 = max(0, x0), y0 = max(0, y0), x1 = min(width, x1), y1 = min(height, y1)
        guard x1 - x0 > 1, y1 - y0 > 1 else { return 0 }
        var sum = 0.0, squares = 0.0
        let length = vDSP_Length(x1 - x0)
        values.withUnsafeBufferPointer { pointer in
            for y in y0..<y1 {
                let row = pointer.baseAddress! + y * width + x0
                var s: Float = 0, q: Float = 0
                vDSP_sve(row, 1, &s, length)
                vDSP_svesq(row, 1, &q, length)
                sum += Double(s)
                squares += Double(q)
            }
        }
        let count = Double((x1 - x0) * (y1 - y0))
        let mean = sum / count
        return max(0, squares / count - mean * mean)
    }

    /// Vision-Rechteck (normalisiert, Ursprung unten links) → Pixelbereich.
    func variance(normalizedVisionRect rect: CGRect) -> Double {
        let x0 = Int(rect.minX * CGFloat(width))
        let x1 = Int(rect.maxX * CGFloat(width))
        let y0 = Int((1 - rect.maxY) * CGFloat(height))
        let y1 = Int((1 - rect.minY) * CGFloat(height))
        return variance(x0: x0, y0: y0, x1: max(x1, x0 + 4), y1: max(y1, y0 + 4))
    }

    /// Schärfe des schärfsten Bildbereichs – so zählt ein scharfes Motiv vor unscharfem Hintergrund (Bokeh) als scharf.
    func peakVariance(grid: Int) -> Double {
        var tiles: [Double] = []
        for gy in 0..<grid {
            for gx in 0..<grid {
                tiles.append(variance(x0: gx * width / grid, y0: gy * height / grid,
                                      x1: (gx + 1) * width / grid, y1: (gy + 1) * height / grid))
            }
        }
        let top = tiles.sorted(by: >).prefix(2)
        return top.reduce(0, +) / Double(max(top.count, 1))
    }
}
