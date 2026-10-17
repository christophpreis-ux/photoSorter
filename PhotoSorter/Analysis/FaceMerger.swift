import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import ImageIO
import UniformTypeIdentifiers

struct MergeSwap {
    let personID: Int
    let donor: PhotoItem
}

/// Vorschlag: Basis-Foto plus Personen, deren Gesicht aus einem anderen Foto übernommen werden soll.
struct MergeCandidate {
    let base: PhotoItem
    let swaps: [MergeSwap]
}

struct MergeResult: @unchecked Sendable {
    let image: CIImage
    let base: PhotoItem
    let preview: CGImage?
    let originalPreview: CGImage?
    /// Vorher/Nachher-Ausschnitte pro getauschter Person.
    let faceCrops: [(personID: Int, before: CGImage, after: CGImage)]
    let failedPersons: [Int]
}

/// Setzt ein Gruppenfoto aus mehreren Aufnahmen einer Serie zusammen ("Best Take"):
/// Ausgehend vom besten Foto werden Gesichter mit geschlossenen Augen durch die beste Version
/// derselben Person aus einem anderen Foto ersetzt – komplett on-device mit Vision und Core Image.
enum FaceMerger {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// Maximale mittlere Abweichung der Landmarken nach dem Ausrichten (relativ zur Gesichtsbreite).
    static var maxResidual: CGFloat = 0.03

    // MARK: - Vorschlag

    static func candidate(scene: PhotoScene, evaluation: SceneEvaluation, decisions: [UUID: Decision]) -> MergeCandidate? {
        let people = evaluation.tracks.filter(\.isSignificant)
        guard people.count >= 2, scene.photos.count >= 2 else { return nil }
        let baseID = evaluation.ranking.first { decisions[$0]?.keep == true } ?? evaluation.ranking.first
        guard let baseID, let base = scene.photos.first(where: { $0.id == baseID }) else { return nil }

        var swaps: [MergeSwap] = []
        for person in people {
            guard person.faceIndexByPhoto[base.id] != nil,
                  let donorID = person.bestPhoto, donorID != base.id,
                  let donor = scene.photos.first(where: { $0.id == donorID }) else { continue }
            let baseFace = evaluation.evaluations[base.id]?.faces.first { $0.trackID == person.id }
            let donorFace = evaluation.evaluations[donorID]?.faces.first { $0.trackID == person.id }
            guard let baseFace, let donorFace, !donorFace.eyesClosed else { continue }
            let baseScore = person.scoreByPhoto[base.id] ?? 0
            let donorScore = person.scoreByPhoto[donorID] ?? 0
            if baseFace.eyesClosed || baseScore < donorScore - 0.2 {
                swaps.append(MergeSwap(personID: person.id, donor: donor))
            }
        }
        return swaps.isEmpty ? nil : MergeCandidate(base: base, swaps: swaps)
    }

    // MARK: - Zusammensetzen

    static func merge(_ candidate: MergeCandidate, tracks: [PersonTrack]) -> MergeResult? {
        guard let baseImage = loadFullImage(candidate.base.primaryURL) else { return nil }
        let extent = baseImage.extent
        let baseFaces = detectFaces(in: baseImage)
        var output = baseImage
        var donorCache: [URL: (CIImage, [VNFaceObservation])] = [:]
        var swappedRects: [(Int, CGRect)] = []
        var failed: [Int] = []

        for swap in candidate.swaps {
            guard let track = tracks.first(where: { $0.id == swap.personID }),
                  let baseIndex = track.faceIndexByPhoto[candidate.base.id],
                  let donorIndex = track.faceIndexByPhoto[swap.donor.id],
                  let baseBox = candidate.base.analysis?.faces[baseIndex].boundingBox,
                  let donorBox = swap.donor.analysis?.faces[donorIndex].boundingBox else {
                failed.append(swap.personID)
                continue
            }
            if donorCache[swap.donor.primaryURL] == nil, let image = loadFullImage(swap.donor.primaryURL) {
                donorCache[swap.donor.primaryURL] = (image, detectFaces(in: image))
            }
            guard let (donorImage, donorFaces) = donorCache[swap.donor.primaryURL],
                  let baseFace = nearest(baseFaces, to: baseBox),
                  let donorFace = nearest(donorFaces, to: donorBox),
                  let basePoints = innerPoints(baseFace, imageSize: extent.size),
                  let donorPoints = innerPoints(donorFace, imageSize: donorImage.extent.size),
                  let baseOutline = baseFace.landmarks?.allPoints?.pointsInImage(imageSize: extent.size),
                  basePoints.count == donorPoints.count, basePoints.count >= 20,
                  let transform = similarityTransform(from: donorPoints, to: basePoints) else {
                failed.append(swap.personID)
                continue
            }

            // Ausrichtung prüfen: weichen die Landmarken nach der Transformation zu stark ab (andere Kopfhaltung), lieber nicht tauschen.
            let faceWidth = (basePoints.map(\.x).max() ?? 0) - (basePoints.map(\.x).min() ?? 0)
            let residual = zip(donorPoints, basePoints)
                .map { hypot($0.applying(transform).x - $1.x, $0.applying(transform).y - $1.y) }
                .reduce(0, +) / CGFloat(basePoints.count)
            guard faceWidth > 0, residual / faceWidth < maxResidual else {
                failed.append(swap.personID)
                continue
            }

            let xs = baseOutline.map(\.x), ys = baseOutline.map(\.y)
            let faceRect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            let center = CGPoint(x: faceRect.midX, y: faceRect.midY + faceRect.height * 0.05)
            let radiusX = faceRect.width * 0.58, radiusY = faceRect.height * 0.66

            var warped = donorImage.transformed(by: transform)
            warped = matchColor(warped, to: output, in: CGRect(x: center.x - radiusX * 0.6, y: center.y - radiusY * 0.6,
                                                              width: radiusX * 1.2, height: radiusY * 1.2))
            let mask = ellipseMask(center: center, radiusX: radiusX, radiusY: radiusY, extent: extent)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = warped
            blend.backgroundImage = output
            blend.maskImage = mask
            guard let blended = blend.outputImage?.cropped(to: extent) else {
                failed.append(swap.personID)
                continue
            }
            output = blended
            swappedRects.append((swap.personID, CGRect(x: center.x - radiusX * 1.5, y: center.y - radiusY * 1.4,
                                                       width: radiusX * 3, height: radiusY * 2.8).intersection(extent)))
        }

        guard !swappedRects.isEmpty else {
            return MergeResult(image: baseImage, base: candidate.base, preview: nil, originalPreview: nil,
                               faceCrops: [], failedPersons: failed)
        }

        // Das Ergebnis bleibt ein (speichersparender) Core-Image-Graph – gerendert wird erst für Vorschau und Speichern.
        let crops = swappedRects.compactMap { personID, rect -> (Int, CGImage, CGImage)? in
            guard let before = render(baseImage, rect: rect, maxPixel: 360),
                  let after = render(output, rect: rect, maxPixel: 360) else { return nil }
            return (personID, before, after)
        }
        return MergeResult(image: output, base: candidate.base,
                           preview: render(output, rect: extent, maxPixel: 1800),
                           originalPreview: render(baseImage, rect: extent, maxPixel: 1800),
                           faceCrops: crops.map { (personID: $0.0, before: $0.1, after: $0.2) },
                           failedPersons: failed)
    }

    /// Speichert das kombinierte Foto neben dem Original (RAW → 16-Bit-TIFF, sonst JPEG) mit den Metadaten des Basisfotos.
    static func save(_ result: MergeResult, to destination: URL? = nil) throws -> URL {
        let base = result.base
        let folder = destination ?? base.primaryURL.deletingLastPathComponent()
        let isRaw = base.isRawPrimary
        let ext = isRaw ? "tif" : "jpg"
        var url = folder.appendingPathComponent("\(base.baseName)_Kombiniert.\(ext)")
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            url = folder.appendingPathComponent("\(base.baseName)_Kombiniert_\(counter).\(ext)")
        }

        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        guard let cgImage = context.createCGImage(result.image, from: result.image.extent,
                                                  format: isRaw ? .RGBA16 : .RGBA8, colorSpace: space) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [:]
        if let source = CGImageSourceCreateWithURL(base.primaryURL as CFURL, nil),
           let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            properties = original
        }
        // Ausrichtung wurde bereits angewendet.
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            tiff[kCGImagePropertyTIFFSoftware] = "PhotoSorter (kombiniert)"
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        properties[kCGImageDestinationLossyCompressionQuality] = 0.95

        let type = (isRaw ? UTType.tiff : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }

    // MARK: - Hilfsfunktionen

    static func loadFullImage(_ url: URL) -> CIImage? {
        let image: CIImage?
        if PhotosLibrary.isPhotosURL(url) {
            image = PhotosLibrary.fullImage(for: url)
        } else if PhotoScanner.rawExtensions.contains(url.pathExtension.lowercased()) {
            image = CIRAWFilter(imageURL: url)?.outputImage
        } else {
            image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        }
        guard let image else { return nil }
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    private static func detectFaces(in image: CIImage) -> [VNFaceObservation] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        return request.results ?? []
    }

    /// Augen, Brauen, Nase und Mund – stabiler für die Ausrichtung als die Gesichtskontur.
    private static func innerPoints(_ face: VNFaceObservation, imageSize: CGSize) -> [CGPoint]? {
        guard let landmarks = face.landmarks else { return nil }
        let regions = [landmarks.leftEye, landmarks.rightEye, landmarks.leftEyebrow, landmarks.rightEyebrow,
                       landmarks.nose, landmarks.outerLips]
        var points: [CGPoint] = []
        for region in regions {
            guard let region else { return nil }
            points += region.pointsInImage(imageSize: imageSize)
        }
        return points
    }

    private static func nearest(_ faces: [VNFaceObservation], to box: CGRect) -> VNFaceObservation? {
        let best = faces.min {
            hypot($0.boundingBox.midX - box.midX, $0.boundingBox.midY - box.midY)
                < hypot($1.boundingBox.midX - box.midX, $1.boundingBox.midY - box.midY)
        }
        guard let best, hypot(best.boundingBox.midX - box.midX, best.boundingBox.midY - box.midY) < box.width * 0.8 else { return nil }
        return best
    }

    /// Ähnlichkeitstransformation (Skalierung, Rotation, Verschiebung) nach der Methode der kleinsten Quadrate.
    static func similarityTransform(from source: [CGPoint], to target: [CGPoint]) -> CGAffineTransform? {
        let n = CGFloat(source.count)
        let meanSource = CGPoint(x: source.map(\.x).reduce(0, +) / n, y: source.map(\.y).reduce(0, +) / n)
        let meanTarget = CGPoint(x: target.map(\.x).reduce(0, +) / n, y: target.map(\.y).reduce(0, +) / n)
        var a: CGFloat = 0, b: CGFloat = 0, norm: CGFloat = 0
        for (p, q) in zip(source, target) {
            let px = p.x - meanSource.x, py = p.y - meanSource.y
            let qx = q.x - meanTarget.x, qy = q.y - meanTarget.y
            a += px * qx + py * qy
            b += px * qy - py * qx
            norm += px * px + py * py
        }
        guard norm > 0 else { return nil }
        let c = a / norm, s = b / norm
        let tx = meanTarget.x - (c * meanSource.x - s * meanSource.y)
        let ty = meanTarget.y - (s * meanSource.x + c * meanSource.y)
        return CGAffineTransform(a: c, b: s, c: -s, d: c, tx: tx, ty: ty)
    }

    private static func ellipseMask(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, extent: CGRect) -> CIImage {
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = 62
        gradient.radius1 = 100
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1)
        gradient.color1 = CIColor(red: 0, green: 0, blue: 0)
        let transform = CGAffineTransform(scaleX: radiusX / 100, y: radiusY / 100)
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return (gradient.outputImage ?? CIImage.black).transformed(by: transform).cropped(to: extent)
    }

    /// Gleicht Helligkeit/Farbe des eingesetzten Gesichts an das Basisfoto an.
    private static func matchColor(_ image: CIImage, to reference: CIImage, in rect: CGRect) -> CIImage {
        guard let source = average(image, rect), let target = average(reference, rect) else { return image }
        func gain(_ i: Int) -> CGFloat { CGFloat(min(max(target[i] / max(source[i], 0.001), 0.85), 1.18)) }
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: gain(0), y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: gain(1), z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: gain(2), w: 0)
        return matrix.outputImage ?? image
    }

    private static func average(_ image: CIImage, _ rect: CGRect) -> [Float]? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = rect
        guard let output = filter.outputImage else { return nil }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return pixel
    }

    private static func render(_ image: CIImage, rect: CGRect, maxPixel: CGFloat) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scale = min(1, maxPixel / max(rect.width, rect.height))
        let scaled = image.cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}
