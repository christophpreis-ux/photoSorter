import Foundation
import Vision

struct GroupingSettings: Equatable {
    /// Fotos innerhalb dieser Zeit gelten als Serie (Burst).
    var burstGap: TimeInterval = 2
    /// Maximaler Abstand, damit ähnliche Fotos noch zur selben Szene gehören.
    var sceneGap: TimeInterval = 120
    /// Feature-Print-Distanz, unter der zwei Fotos als "ähnlich" gelten.
    var similarityThreshold: Float = 0.5
}

/// Teilt die Fotos chronologisch in Szenen: Fotos landen in derselben Szene,
/// wenn sie zeitlich nah beieinander liegen und inhaltlich ähnlich sind.
enum SceneGrouper {
    static func group(_ photos: [PhotoItem], settings: GroupingSettings) -> [[PhotoItem]] {
        let sorted = photos.sorted {
            $0.captureDate != $1.captureDate ? $0.captureDate < $1.captureDate
                : $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending
        }
        var groups: [[PhotoItem]] = []
        var current: [PhotoItem] = []

        for photo in sorted {
            guard let last = current.last else {
                current = [photo]
                continue
            }
            let gap = photo.captureDate.timeIntervalSince(last.captureDate)
            let distance = current.suffix(3).compactMap { self.distance(photo, $0) }.min()

            let joins: Bool
            if let distance {
                joins = (gap <= settings.burstGap && distance < settings.similarityThreshold * 1.6)
                    || (gap <= settings.sceneGap && distance < settings.similarityThreshold)
            } else {
                joins = gap <= settings.burstGap
            }

            if joins {
                current.append(photo)
            } else {
                groups.append(current)
                current = [photo]
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    static func distance(_ a: PhotoItem, _ b: PhotoItem) -> Float? {
        guard let fa = a.analysis?.featurePrint, let fb = b.analysis?.featurePrint else { return nil }
        var distance: Float = 0
        do {
            try fa.computeDistance(&distance, to: fb)
            return distance
        } catch {
            return nil
        }
    }
}
