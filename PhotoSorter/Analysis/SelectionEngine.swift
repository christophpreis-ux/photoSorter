import Foundation
import CoreGraphics

/// Bewertung eines Gesichts innerhalb einer Szene.
struct FaceEvaluation {
    var trackID: Int
    /// 0…1, absolut geschätzte Augenöffnung.
    var eyeOpenness: Double
    var eyesClosed: Bool
    var lookingAway: Bool
    var score: Double
}

struct PhotoEvaluation {
    var quality: Double
    var sharpness: Double
    var exposure: Double
    var aesthetics: Double
    var faceScore: Double?
    var faces: [FaceEvaluation]
    var issues: Set<PhotoIssue>
}

/// Eine Person, die über mehrere Fotos einer Szene hinweg verfolgt wird (über die Position im Bild).
struct PersonTrack: Identifiable {
    let id: Int
    var faceIndexByPhoto: [UUID: Int] = [:]
    var scoreByPhoto: [UUID: Double] = [:]
    var goodPhotos: Set<UUID> = []
    var bestPhoto: UUID?
    var isSignificant = false
}

struct SceneEvaluation {
    let ranking: [UUID]
    let evaluations: [UUID: PhotoEvaluation]
    let tracks: [PersonTrack]
    let isGroupScene: Bool
    /// Paare fast identischer Fotos.
    let nearDuplicates: [UUID: [UUID]]
}

/// Bewertet Fotos und entscheidet je nach Strenge, welche behalten werden.
enum SelectionEngine {
    static let duplicateDistance: Float = 0.12

    // MARK: - Bewertung (einmal pro Szene, unabhängig vom Schieberegler)

    static func evaluate(scene: PhotoScene) -> SceneEvaluation {
        let photos = scene.photos
        let count = photos.count
        let tracks = buildTracks(photos)

        // Maximalwerte pro Person für relative Vergleiche (Blinzeln, Gesichtsschärfe).
        var trackMaxEye: [Int: Double] = [:]
        var trackMaxSharp: [Int: Double] = [:]
        var trackMaxQuality: [Int: Double] = [:]
        for track in tracks {
            for (photoID, faceIndex) in track.faceIndexByPhoto {
                guard let face = photos.first(where: { $0.id == photoID })?.analysis?.faces[faceIndex] else { continue }
                if let ear = usableEyeAspect(face) { trackMaxEye[track.id] = max(trackMaxEye[track.id] ?? 0, ear) }
                trackMaxSharp[track.id] = max(trackMaxSharp[track.id] ?? 0, face.sharpness)
                trackMaxQuality[track.id] = max(trackMaxQuality[track.id] ?? 0, Double(face.captureQuality ?? 0))
            }
        }

        let maxPeak = photos.compactMap { $0.analysis?.peakSharpness }.max() ?? 1
        var evaluations: [UUID: PhotoEvaluation] = [:]
        var mutableTracks = tracks

        for photo in photos {
            guard let analysis = photo.analysis else {
                evaluations[photo.id] = PhotoEvaluation(quality: 0.5, sharpness: 0.5, exposure: 0.5, aesthetics: 0.5,
                                                        faceScore: nil, faces: [], issues: [])
                continue
            }

            // Schärfe: absolut (großzügig) + relativ zur schärfsten Aufnahme der Szene.
            let sharpAbs = clamp((log10(max(analysis.peakSharpness, 1)) - 1.3) / 1.0)
            let sharpRel = clamp(1 - log10(max(maxPeak, 1) / max(analysis.peakSharpness, 1)) / 0.8)
            let sharpness = count > 1 ? 0.4 * sharpAbs + 0.6 * sharpRel : sharpAbs

            // Belichtung
            var exposure = 1.0
            exposure -= clamp(analysis.highlightClipping * 4) * 0.6
            exposure -= clamp(analysis.shadowClipping * 3) * 0.4
            exposure -= max(0, abs(analysis.meanLuma - 0.5) - 0.25) * 2
            exposure = clamp(exposure)

            let aesthetics = analysis.aesthetics.map { clamp((Double($0) + 1) / 2) } ?? 0.5

            var issues: Set<PhotoIssue> = []
            if sharpAbs < 0.2 || (count > 1 && sharpRel < 0.3) { issues.insert(.blurry) }
            if analysis.highlightClipping > 0.15 { issues.insert(.overexposed) }
            if analysis.meanLuma < 0.12 && analysis.shadowClipping > 0.3 { issues.insert(.underexposed) }

            // Gesichter
            var faceEvaluations: [FaceEvaluation] = []
            for (faceIndex, face) in analysis.faces.enumerated() {
                guard let track = tracks.first(where: { $0.faceIndexByPhoto[photo.id] == faceIndex }) else { continue }
                let lookingAway = abs(face.yaw ?? 0) > 1.0
                var openness = 0.75
                var closed = false
                if let ear = usableEyeAspect(face) {
                    let absolute = clamp((ear - 0.12) / 0.12)
                    let maxEar = trackMaxEye[track.id] ?? ear
                    let relative = track.faceIndexByPhoto.count > 1 && maxEar > 0 ? ear / maxEar : 1
                    openness = min(absolute, clamp((relative - 0.45) / 0.4))
                    closed = absolute < 0.25 || (relative < 0.6 && absolute < 0.8)
                }
                let quality = Double(face.captureQuality ?? 0.3)
                let qualityRel = (trackMaxQuality[track.id] ?? 0) > 0 ? quality / trackMaxQuality[track.id]! : 0.5
                let faceSharp = clamp(1 - log10(max(trackMaxSharp[track.id] ?? 1, 1) / max(face.sharpness, 1)) / 0.8)
                var score = 0.25 * clamp(quality / 0.6) + 0.2 * qualityRel + 0.35 * openness + 0.2 * faceSharp
                if lookingAway { score -= 0.15 }
                if closed { score -= 0.2 }
                score = clamp(score)
                faceEvaluations.append(FaceEvaluation(trackID: track.id, eyeOpenness: openness, eyesClosed: closed,
                                                      lookingAway: lookingAway, score: score))
                if let i = mutableTracks.firstIndex(where: { $0.id == track.id }) {
                    mutableTracks[i].scoreByPhoto[photo.id] = closed ? score * 0.5 : score
                }
            }
            if faceEvaluations.contains(where: \.eyesClosed) { issues.insert(.eyesClosed) }
            if analysis.category == .portrait, faceEvaluations.first?.lookingAway == true { issues.insert(.lookingAway) }

            var faceScore: Double?
            if !faceEvaluations.isEmpty {
                let scores = faceEvaluations.map(\.score)
                faceScore = 0.6 * scores.reduce(0, +) / Double(scores.count) + 0.4 * (scores.min() ?? 0)
            }

            let quality: Double
            if let faceScore {
                quality = 0.30 * sharpness + 0.40 * faceScore + 0.15 * aesthetics + 0.15 * exposure
            } else {
                quality = 0.55 * sharpness + 0.25 * aesthetics + 0.20 * exposure
            }
            evaluations[photo.id] = PhotoEvaluation(quality: quality, sharpness: sharpness, exposure: exposure,
                                                    aesthetics: aesthetics, faceScore: faceScore,
                                                    faces: faceEvaluations, issues: issues)
        }

        // Für jede Person: auf welchen Fotos sieht sie gut aus?
        let minAppearances = count <= 2 ? 1 : Int(ceil(Double(count) * 0.5))
        for i in mutableTracks.indices {
            let scores = mutableTracks[i].scoreByPhoto
            guard let best = scores.max(by: { $0.value < $1.value }) else { continue }
            mutableTracks[i].bestPhoto = best.key
            mutableTracks[i].goodPhotos = Set(scores.filter { $0.value >= best.value - 0.08 }.map(\.key))
            mutableTracks[i].isSignificant = mutableTracks[i].faceIndexByPhoto.count >= minAppearances
        }

        let ranking = photos.map(\.id).sorted { (evaluations[$0]?.quality ?? 0) > (evaluations[$1]?.quality ?? 0) }

        // Fast identische Fotos finden.
        var duplicates: [UUID: [UUID]] = [:]
        for i in 0..<count {
            for j in (i + 1)..<min(count, i + 25) where j < count {
                if let d = SceneGrouper.distance(photos[i], photos[j]), d < duplicateDistance {
                    duplicates[photos[i].id, default: []].append(photos[j].id)
                    duplicates[photos[j].id, default: []].append(photos[i].id)
                }
            }
        }

        let isGroup = mutableTracks.filter(\.isSignificant).count >= 2
        return SceneEvaluation(ranking: ranking, evaluations: evaluations, tracks: mutableTracks,
                               isGroupScene: isGroup, nearDuplicates: duplicates)
    }

    // MARK: - Entscheidung (bei jeder Bewegung des Schiebereglers)

    /// - Parameter strictness: 0 = nichts aussortieren, 1 = pro Szene nur das Beste behalten.
    static func decide(_ eval: SceneEvaluation, strictness s: Double, overrides: [UUID: Bool]) -> [UUID: Decision] {
        let ranking = eval.ranking
        guard let bestID = ranking.first else { return [:] }
        let quality = { (id: UUID) in eval.evaluations[id]?.quality ?? 0 }
        let issues = { (id: UUID) in eval.evaluations[id]?.issues ?? [] }

        var keep: Set<UUID> = []
        var reasons: [UUID: String] = [:]
        var extraIssues: [UUID: Set<PhotoIssue>] = [:]

        if s <= 0.001 {
            keep = Set(ranking)
            ranking.forEach { reasons[$0] = "Strenge auf Minimum" }
        } else if ranking.count == 1 {
            let bad = issues(bestID).contains(.blurry) || issues(bestID).contains(.eyesClosed)
            if (s >= 0.6 && bad) || (s >= 0.85 && quality(bestID) < 0.4) {
                reasons[bestID] = bad ? "Einzelfoto mit Mängeln: " + issueText(issues(bestID)) : "Einzelfoto mit geringer Qualität"
            } else {
                keep.insert(bestID)
                reasons[bestID] = "Einzelfoto"
            }
        } else {
            keep.insert(bestID)
            reasons[bestID] = "Bestes Foto der Szene"
            let margin = 0.45 * pow(1 - s, 1.6)
            let maxKeep = max(1, Int(ceil(Double(ranking.count) * pow(1 - s, 1.3))))
            let bestIssues = issues(bestID)

            for id in ranking.dropFirst() {
                let photoIssues = issues(id)
                // Mängel, die das beste Foto nicht hat, wiegen schwer.
                let avoidable = photoIssues.subtracting(bestIssues).intersection([.eyesClosed, .blurry, .lookingAway])
                if s >= 0.25, !avoidable.isEmpty {
                    reasons[id] = issueText(avoidable) + " – es gibt bessere Alternativen"
                    continue
                }
                if quality(id) < quality(bestID) - margin {
                    reasons[id] = "Deutlich schwächer als das beste Foto"
                    continue
                }
                if keep.count >= maxKeep {
                    reasons[id] = "Es gibt genug bessere Versionen"
                    continue
                }
                if s >= 0.5, let dupes = eval.nearDuplicates[id], dupes.contains(where: { keep.contains($0) }) {
                    reasons[id] = "Fast identisch mit einem besseren Foto"
                    extraIssues[id] = [.duplicate]
                    continue
                }
                keep.insert(id)
                reasons[id] = "Fast so gut wie das beste Foto"
            }
        }

        // Gruppenfotos: Für jede Person muss mindestens ein Foto dabei sein, auf dem sie gut aussieht.
        let people = eval.tracks.filter(\.isSignificant)
        var uncovered = people.filter { $0.goodPhotos.isDisjoint(with: keep) }
        while !uncovered.isEmpty {
            let candidates = Set(uncovered.flatMap(\.goodPhotos)).subtracting(keep)
            guard let pick = candidates.max(by: { a, b in
                let ca = uncovered.filter { $0.goodPhotos.contains(a) }.count
                let cb = uncovered.filter { $0.goodPhotos.contains(b) }.count
                return ca != cb ? ca < cb : quality(a) < quality(b)
            }) else { break }
            let covered = uncovered.filter { $0.goodPhotos.contains(pick) }
            keep.insert(pick)
            if people.count > 1 {
                let names = covered.map { "Person \($0.id + 1)" }.joined(separator: ", ")
                reasons[pick] = "Beste Version für \(names)"
            } else {
                reasons[pick] = "Beste Version des Gesichts"
            }
            extraIssues[pick] = nil
            uncovered.removeAll { $0.goodPhotos.contains(pick) }
        }

        var decisions: [UUID: Decision] = [:]
        for id in ranking {
            var keepIt = keep.contains(id)
            var reason = reasons[id] ?? ""
            let manual = overrides[id]
            if let manual {
                keepIt = manual
                reason = manual ? "Manuell behalten" : "Manuell aussortiert"
            }
            decisions[id] = Decision(keep: keepIt, isBest: id == bestID && ranking.count > 1, isManual: manual != nil,
                                     score: quality(id), reason: reason,
                                     issues: issues(id).union(extraIssues[id] ?? []))
        }
        return decisions
    }

    // MARK: - Hilfsfunktionen

    /// Ordnet Gesichter über alle Fotos einer Szene Personen zu (anhand Position und Größe).
    private static func buildTracks(_ photos: [PhotoItem]) -> [PersonTrack] {
        var tracks: [PersonTrack] = []
        var lastBox: [Int: CGRect] = [:]
        let reference = photos.max { ($0.analysis?.faces.count ?? 0) < ($1.analysis?.faces.count ?? 0) }
        let order = (reference.map { [$0] } ?? []) + photos.filter { $0.id != reference?.id }

        for photo in order {
            let faces = photo.analysis?.faces ?? []
            var pairs: [(face: Int, track: Int, distance: CGFloat)] = []
            for (fi, face) in faces.enumerated() {
                for (ti, track) in tracks.enumerated() {
                    guard let box = lastBox[track.id] else { continue }
                    let size = max(face.boundingBox.width, box.width)
                    let distance = hypot(face.boundingBox.midX - box.midX, face.boundingBox.midY - box.midY) / size
                    let ratio = face.boundingBox.width / max(box.width, 0.0001)
                    if distance < 1.0, ratio > 0.6, ratio < 1.6 { pairs.append((fi, ti, distance)) }
                }
            }
            var usedFaces = Set<Int>(), usedTracks = Set<Int>()
            for pair in pairs.sorted(by: { $0.distance < $1.distance })
            where !usedFaces.contains(pair.face) && !usedTracks.contains(pair.track) {
                usedFaces.insert(pair.face)
                usedTracks.insert(pair.track)
                tracks[pair.track].faceIndexByPhoto[photo.id] = pair.face
                lastBox[tracks[pair.track].id] = faces[pair.face].boundingBox
            }
            for (fi, face) in faces.enumerated() where !usedFaces.contains(fi) {
                var track = PersonTrack(id: tracks.count)
                track.faceIndexByPhoto[photo.id] = fi
                lastBox[track.id] = face.boundingBox
                tracks.append(track)
            }
        }
        // Personen von links nach rechts nummerieren.
        let sorted = tracks.sorted { (lastBox[$0.id]?.midX ?? 0) < (lastBox[$1.id]?.midX ?? 0) }
        return sorted.enumerated().map { index, track in
            var renumbered = PersonTrack(id: index)
            renumbered.faceIndexByPhoto = track.faceIndexByPhoto
            return renumbered
        }
    }

    /// Bei Profilaufnahmen sind die Augen-Landmarken unzuverlässig.
    private static func usableEyeAspect(_ face: FaceInfo) -> Double? {
        guard abs(face.yaw ?? 0) < 1.2 else { return nil }
        return face.eyeAspect
    }

    private static func issueText(_ issues: Set<PhotoIssue>) -> String {
        PhotoIssue.allCases.filter(issues.contains).map(\.title).joined(separator: ", ")
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}
