import Foundation
import CoreGraphics
import Vision

/// Grobe Einordnung eines Fotos – wird für die Umbenennung der behaltenen Fotos genutzt.
enum PhotoCategory: String, CaseIterable, Codable {
    case group, portrait, animal, other

    var title: String {
        switch self {
        case .group: "Gruppenfoto"
        case .portrait: "Porträt"
        case .animal: "Tier"
        case .other: "Motiv"
        }
    }

    /// Präfix für Dateinamen (ohne Umlaute, damit es überall funktioniert).
    var filePrefix: String {
        switch self {
        case .group: "Gruppenfoto"
        case .portrait: "Portrait"
        case .animal: "Tier"
        case .other: "Motiv"
        }
    }

    var symbol: String {
        switch self {
        case .group: "person.3.fill"
        case .portrait: "person.crop.square.fill"
        case .animal: "pawprint.fill"
        case .other: "photo.fill"
        }
    }
}

/// Ein erkanntes Gesicht mit allem, was für die Bewertung wichtig ist.
struct FaceInfo {
    /// Normalisiert, Vision-Koordinaten (Ursprung unten links).
    var boundingBox: CGRect
    /// Apples Gesichts-Aufnahmequalität (0…1), berücksichtigt Schärfe, Ausdruck, Licht.
    var captureQuality: Float?
    /// Höhe/Breite des linken bzw. rechten Auges (Eye Aspect Ratio).
    var leftEyeAspect: Double?
    var rightEyeAspect: Double?
    /// Kopfdrehung in Radiant.
    var yaw: Double?
    /// Laplace-Varianz im Gesichtsbereich (Schärfe).
    var sharpness: Double

    var area: Double { Double(boundingBox.width * boundingBox.height) }

    var eyeAspect: Double? {
        let values = [leftEyeAspect, rightEyeAspect].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct PhotoAnalysis {
    var featurePrint: VNFeaturePrintObservation?
    /// Nur relevante Gesichter (keine winzigen Hintergrundgesichter).
    var faces: [FaceInfo]
    /// Schärfe der schärfsten Bildregion (Motiv), Laplace-Varianz.
    var peakSharpness: Double
    var globalSharpness: Double
    var meanLuma: Double
    var highlightClipping: Double
    var shadowClipping: Double
    /// Apple Aesthetics Score (-1…1).
    var aesthetics: Float?
    var isUtility: Bool
    var hasAnimal: Bool
    /// Vision-Bildklassifikation (Label → Konfidenz), z. B. "bride", "sparkling_wine", "stained_glass".
    var labels: [String: Float]
    var category: PhotoCategory
    /// Kleines JPEG für die Übersicht.
    var thumbnailData: Data?
    var pixelSize: CGSize
}

/// Ein "Foto" – kann aus mehreren Dateien bestehen (z. B. RAW + JPEG + XMP).
final class PhotoItem: Identifiable, Hashable, @unchecked Sendable {
    let id = UUID()
    let baseName: String
    let files: [URL]
    let primaryURL: URL
    var captureDate: Date
    var analysis: PhotoAnalysis?
    /// Favorit in Apple Fotos – wird immer behalten.
    var isFavorite = false
    /// Gesamtgröße aller Dateien des Fotos (RAW + JPEG + XMP) in Bytes.
    var byteSize: Int64 = 0

    init(baseName: String, files: [URL], primaryURL: URL, captureDate: Date) {
        self.baseName = baseName
        self.files = files
        self.primaryURL = primaryURL
        self.captureDate = captureDate
    }

    var isRawPrimary: Bool { PhotoScanner.rawExtensions.contains(primaryURL.pathExtension.lowercased()) }
    var hasRaw: Bool { files.contains { PhotoScanner.rawExtensions.contains($0.pathExtension.lowercased()) } }
    var category: PhotoCategory { analysis?.category ?? .other }

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Eine Szene: zeitlich und inhaltlich zusammengehörige Fotos.
struct PhotoScene: Identifiable {
    let id = UUID()
    let index: Int
    var photos: [PhotoItem]

    var category: PhotoCategory {
        let cats = photos.map(\.category)
        if cats.contains(.group) { return .group }
        let counts = Dictionary(grouping: cats, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? .other
    }

    var startDate: Date { photos.first?.captureDate ?? .distantPast }
}

enum PhotoIssue: String, Hashable, CaseIterable {
    case eyesClosed, blurry, lookingAway, overexposed, underexposed, duplicate

    var title: String {
        switch self {
        case .eyesClosed: "Augen geschlossen"
        case .blurry: "Unscharf"
        case .lookingAway: "Blick abgewandt"
        case .overexposed: "Überbelichtet"
        case .underexposed: "Unterbelichtet"
        case .duplicate: "Fast identisch"
        }
    }

    var symbol: String {
        switch self {
        case .eyesClosed: "eye.slash.fill"
        case .blurry: "camera.metering.unknown"
        case .lookingAway: "person.fill.turn.left"
        case .overexposed: "sun.max.fill"
        case .underexposed: "moon.fill"
        case .duplicate: "square.on.square"
        }
    }
}

struct Decision {
    var keep: Bool
    var isFavorite = false
    var isBest: Bool
    var isManual: Bool
    var score: Double
    var reason: String
    var issues: Set<PhotoIssue>
}

enum SceneFilter: String, CaseIterable, Identifiable {
    case all, withRejects, series, groups, portraits, mergeable
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Alle Szenen"
        case .withRejects: "Mit Aussortierten"
        case .series: "Nur Serien"
        case .groups: "Gruppenfotos"
        case .portraits: "Porträts"
        case .mergeable: "Kombinierbar"
        }
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
