import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Art eines Abschnitts – bestimmt den Ordnernamen (und damit das Lightroom-Preset).
enum EventKind: String, CaseIterable, Identifiable {
    case gettingReady, ceremonyChurch, ceremonyCivil, ceremonyOutdoor, reception, groupPhotos, couple, dinner, party, details, portraits, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingReady: "Getting Ready"
        case .ceremonyChurch: "Trauung Kirche"
        case .ceremonyCivil: "Trauung Standesamt"
        case .ceremonyOutdoor: "Freie Trauung"
        case .reception: "Sektempfang"
        case .groupPhotos: "Gruppenfotos"
        case .couple: "Paarshooting"
        case .dinner: "Essen"
        case .party: "Party"
        case .details: "Details"
        case .portraits: "Porträts"
        case .other: "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .gettingReady: "comb.fill"
        case .ceremonyChurch: "building.columns.fill"
        case .ceremonyCivil: "signature"
        case .ceremonyOutdoor: "leaf.fill"
        case .reception: "wineglass.fill"
        case .groupPhotos: "person.3.fill"
        case .couple: "heart.fill"
        case .dinner: "fork.knife"
        case .party: "music.note"
        case .details: "sparkles"
        case .portraits: "person.crop.square.fill"
        case .other: "photo.on.rectangle"
        }
    }

    /// Gewichte für Vision-Labels.
    fileprivate var labelWeights: [String: Double] {
        switch self {
        case .gettingReady:
            ["cosmetic_tool": 3, "bathrobe": 3, "bedroom": 2, "bathroom_room": 2, "bathroom": 1.5, "washbasin": 1.5,
             "high_heel": 2, "closet": 1.5, "bed": 1.5, "jewelry": 1, "wedding_dress": 0.8, "curtain": 0.4]
        case .ceremonyChurch:
            ["stained_glass": 4, "organ_instrument": 4, "belltower": 2, "candlestick": 1.5, "ceremony": 1.5,
             "arch": 1, "dome": 1, "chandelier": 0.6, "auditorium": 0.8, "candle": 0.5]
        case .ceremonyCivil:
            ["ceremony": 1.5, "conference": 1.5, "desk": 1.5, "document": 1.5, "podium": 1.5, "pen": 1,
             "office_supplies": 1, "flag": 1, "interior_room": 0.4, "bouquet": 0.4]
        case .ceremonyOutdoor:
            ["ceremony": 1.5, "pergola": 1.5, "folding_chair": 1.5, "gazebo": 1, "arch": 1,
             "flower_arrangement": 0.8, "garden": 0.8]
        case .reception:
            ["sparkling_wine": 4, "drinking_glass": 2.5, "cocktail": 2, "white_wine": 2, "wine": 1.5, "drink": 1.5,
             "liquor": 1, "celebration": 1, "crowd": 1, "patio": 0.8, "garden": 0.4, "people": 0.3]
        case .groupPhotos:
            ["crowd": 0.8, "people": 0.5, "suit": 0.3, "gown": 0.3]
        case .couple:
            ["bride": 1, "groom": 1, "wedding_dress": 0.5, "sunset_sunrise": 1.5, "lake": 0.8, "forest": 0.8,
             "park": 0.5, "beach": 0.8, "grass": 0.3]
        case .dinner:
            ["dining_room": 2.5, "tableware": 2.5, "food": 2, "plate": 2, "restaurant": 2, "wedding_cake": 2,
             "fork": 1.5, "cake": 1.5, "dessert": 1.5, "table": 1, "utensil": 1, "wine_bottle": 1, "candle": 0.8,
             "chandelier": 0.5]
        case .party:
            ["dancing": 4, "disco_ball": 4, "nightclub": 3, "deejay": 3, "fireworks": 3, "sparkler": 3,
             "concert": 2.5, "spotlight": 1.5, "music": 1.5, "performance": 1.5, "singer": 1.5,
             "musical_instrument": 1, "night_sky": 1]
        case .details:
            ["flower_arrangement": 2, "bouquet": 2, "decoration": 2, "jewelry": 1.5, "wedding_cake": 1.5,
             "rose": 1, "gift": 1, "vase": 1, "candle": 1, "printed_page": 1, "tableware": 0.5]
        case .portraits, .other:
            [:]
        }
    }

    fileprivate var isCeremony: Bool { [.ceremonyChurch, .ceremonyCivil, .ceremonyOutdoor].contains(self) }
}

/// Ein Abschnitt des Shootings: mehrere aufeinanderfolgende Szenen (z. B. "Sektempfang", 200 Fotos).
struct EventChapter: Identifiable {
    let id = UUID()
    var sceneIDs: [UUID]
    var kind: EventKind
    var name: String
    var isNameCustom = false
    /// Häufigste Bildinhalte – zur Anzeige und für die automatische Benennung.
    var topLabels: [String] = []
}

enum EventDetector {
    // MARK: - Bewertung

    static func scores(for photo: PhotoItem) -> [EventKind: Double] {
        guard let analysis = photo.analysis else { return [:] }
        var result: [EventKind: Double] = [:]
        for kind in EventKind.allCases {
            var score = 0.0
            for (label, weight) in kind.labelWeights {
                score += Double(analysis.labels[label] ?? 0) * weight
            }
            result[kind] = score
        }
        let faces = analysis.faces.count
        let wedding = ["wedding", "bride", "groom", "wedding_dress", "ceremony"]
            .map { Double(analysis.labels[$0] ?? 0) }.reduce(0, +)

        // Gesichter sagen viel über die Art der Aufnahme.
        result[.groupPhotos, default: 0] += faces >= 4 ? 2.5 : faces == 3 ? 1.5 : 0
        // Paarshooting nur, wenn auch Hochzeits-Hinweise (Braut, Bräutigam, Brautkleid …) erkannt werden.
        result[.couple, default: 0] += faces == 2 ? 0.3 + min(wedding, 1) * 1.2 : 0
        result[.portraits, default: 0] += faces == 1 && analysis.category == .portrait ? 1.0 : 0
        result[.details, default: 0] *= faces == 0 ? 1.6 : 0.3
        if faces == 0 { result[.details, default: 0] += 0.3 }
        for kind in EventKind.allCases where kind.isCeremony {
            result[kind, default: 0] *= 1 + min(wedding, 1)
        }
        return result
    }

    private static func meanScores(_ photos: [PhotoItem]) -> [EventKind: Double] {
        var sum: [EventKind: Double] = [:]
        for photo in photos {
            for (kind, value) in scores(for: photo) { sum[kind, default: 0] += value }
        }
        let count = Double(max(photos.count, 1))
        return sum.mapValues { $0 / count }
    }

    static func kind(for photos: [PhotoItem]) -> EventKind {
        let mean = meanScores(photos)
        guard let best = mean.max(by: { $0.value < $1.value }), best.value >= 0.45 else { return .other }
        return best.key
    }

    static func topLabels(_ photos: [PhotoItem], count: Int = 8) -> [String] {
        let ignored: Set = ["people", "adult", "child", "clothing", "structure", "outdoor", "interior_room", "sky",
                            "material", "furniture", "textile", "land", "plant", "vegetation", "light", "daytime"]
        var sum: [String: Float] = [:]
        for photo in photos {
            for (label, value) in photo.analysis?.labels ?? [:] where !ignored.contains(label) {
                sum[label, default: 0] += value
            }
        }
        return sum.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }

    // MARK: - Abschnitte bilden

    static func detect(scenes: [PhotoScene], settings: GroupingSettings) -> [EventChapter] {
        guard !scenes.isEmpty else { return [] }

        // 1. Längere Pausen trennen Abschnitte immer.
        var segments: [[PhotoScene]] = [[scenes[0]]]
        for scene in scenes.dropFirst() {
            let previous = segments[segments.count - 1].last!
            let gap = scene.startDate.timeIntervalSince(previous.photos.last?.captureDate ?? previous.startDate)
            if gap > settings.chapterGap {
                segments.append([scene])
            } else {
                segments[segments.count - 1].append(scene)
            }
        }

        // 2. Innerhalb eines Segments: Wechsel der Art (z. B. Trauung → Gruppenfotos) erkennen.
        var runs: [(kind: EventKind, scenes: [PhotoScene])] = []
        for segment in segments {
            var segmentRuns: [(kind: EventKind, scenes: [PhotoScene])] = []
            for scene in segment {
                let kind = self.kind(for: scene.photos)
                // Einzelne Porträts oder Unklares beginnen keinen neuen Abschnitt.
                let neutral = kind == .portraits || kind == .other
                if let last = segmentRuns.last, last.kind == kind || neutral {
                    segmentRuns[segmentRuns.count - 1].scenes.append(scene)
                } else {
                    segmentRuns.append((kind, [scene]))
                }
            }
            // Kurze Ausreißer dem Nachbarn zuschlagen – echte Abschnitte haben viele Fotos.
            segmentRuns = absorbSmallRuns(segmentRuns, minPhotos: 12)
            // Jeden Lauf als Ganzes neu bewerten.
            segmentRuns = segmentRuns.map { (self.kind(for: $0.scenes.flatMap(\.photos)), $0.scenes) }
            runs.append(contentsOf: segmentRuns)
        }

        // 3. Gleichartige Nachbarn mit kurzer Pause zusammenfassen.
        var merged: [(kind: EventKind, scenes: [PhotoScene])] = []
        for run in runs {
            if let last = merged.last, last.kind == run.kind,
               let lastEnd = last.scenes.last?.photos.last?.captureDate,
               run.scenes[0].startDate.timeIntervalSince(lastEnd) < settings.chapterGap * 3 {
                merged[merged.count - 1].scenes.append(contentsOf: run.scenes)
            } else {
                merged.append(run)
            }
        }

        // 4. Winzige Abschnitte (wenige Fotos) dem zeitlich nächsten Nachbarn zuschlagen, außer bei sehr großer Pause.
        let photoCount = { (run: (kind: EventKind, scenes: [PhotoScene])) in run.scenes.reduce(0) { $0 + $1.photos.count } }
        var index = 0
        while merged.count > 1, index < merged.count {
            guard photoCount(merged[index]) < 5 else { index += 1; continue }
            let start = merged[index].scenes[0].startDate
            let end = merged[index].scenes.last?.photos.last?.captureDate ?? start
            let gapBefore = index > 0 ? start.timeIntervalSince(merged[index - 1].scenes.last?.photos.last?.captureDate ?? start) : .infinity
            let gapAfter = index < merged.count - 1 ? merged[index + 1].scenes[0].startDate.timeIntervalSince(end) : .infinity
            guard min(gapBefore, gapAfter) < 2 * 3600 else { index += 1; continue }
            if gapBefore <= gapAfter {
                merged[index - 1].scenes.append(contentsOf: merged[index].scenes)
            } else {
                merged[index + 1].scenes.insert(contentsOf: merged[index].scenes, at: 0)
            }
            merged.remove(at: index)
            index = 0
        }
        // Art nach dem Zusammenfassen neu bestimmen und gleiche Nachbarn verschmelzen.
        merged = merged.map { (self.kind(for: $0.scenes.flatMap(\.photos)), $0.scenes) }
        var final: [(kind: EventKind, scenes: [PhotoScene])] = []
        for run in merged {
            if let last = final.last, last.kind == run.kind,
               let lastEnd = last.scenes.last?.photos.last?.captureDate,
               run.scenes[0].startDate.timeIntervalSince(lastEnd) < settings.chapterGap * 3 {
                final[final.count - 1].scenes.append(contentsOf: run.scenes)
            } else {
                final.append(run)
            }
        }

        return final.map { run in
            let photos = run.scenes.flatMap(\.photos)
            return EventChapter(sceneIDs: run.scenes.map(\.id), kind: run.kind,
                                name: defaultName(kind: run.kind, start: run.scenes[0].startDate),
                                topLabels: topLabels(photos))
        }
    }

    private static func absorbSmallRuns(_ runs: [(kind: EventKind, scenes: [PhotoScene])], minPhotos: Int)
        -> [(kind: EventKind, scenes: [PhotoScene])] {
        guard runs.count > 1 else { return runs }
        var result = runs
        var changed = true
        while changed && result.count > 1 {
            changed = false
            let counts = result.map { $0.scenes.reduce(0) { $0 + $1.photos.count } }
            guard let index = counts.indices.filter({ counts[$0] < minPhotos }).min(by: { counts[$0] < counts[$1] }) else { break }
            // An den größeren Nachbarn anhängen.
            let left = index > 0 ? counts[index - 1] : -1
            let right = index < result.count - 1 ? counts[index + 1] : -1
            if left >= right {
                result[index - 1].scenes.append(contentsOf: result[index].scenes)
            } else {
                result[index + 1].scenes.insert(contentsOf: result[index].scenes, at: 0)
            }
            result.remove(at: index)
            // Gleiche Nachbarn verschmelzen.
            var i = 1
            while i < result.count {
                if result[i].kind == result[i - 1].kind {
                    result[i - 1].scenes.append(contentsOf: result[i].scenes)
                    result.remove(at: i)
                } else {
                    i += 1
                }
            }
            changed = true
        }
        return result
    }

    static func defaultName(kind: EventKind, start: Date) -> String {
        kind == .other ? "Abschnitt " + start.formatted(.dateTime.hour().minute()) : kind.title
    }

    /// Ordnername für Lightroom, z. B. "03 Sektempfang".
    static func folderName(index: Int, name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(format: "%02d ", index) + (cleaned.isEmpty ? "Abschnitt" : cleaned)
    }
}

/// Benennt unbekannte Abschnitte mit dem On-Device-Sprachmodell von Apple (falls verfügbar).
enum ChapterNamer {
    static func suggestName(labels: [String], photoCount: Int, averageFaces: Double) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability, !labels.isEmpty else { return nil }
            let session = LanguageModelSession(instructions: """
                Du benennst Abschnitte eines Foto-Shootings, damit ein Fotograf sie als Ordner sortieren kann. \
                Antworte ausschließlich mit einem kurzen deutschen Namen aus 1 bis 3 Wörtern, ohne Anführungszeichen \
                und ohne Satzzeichen.
                """)
            let prompt = """
                Erkannte Bildinhalte (englische Labels, häufigste zuerst): \(labels.joined(separator: ", ")). \
                \(photoCount) Fotos, durchschnittlich \(String(format: "%.1f", averageFaces)) Gesichter pro Foto. \
                Wie soll dieser Abschnitt heißen?
                """
            do {
                let response = try await session.respond(to: prompt)
                let name = response.content
                    .components(separatedBy: .newlines).first ?? ""
                let cleaned = name.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
                return cleaned.isEmpty || cleaned.count > 32 ? nil : cleaned
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
