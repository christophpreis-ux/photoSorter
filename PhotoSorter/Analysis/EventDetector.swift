import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Art eines Abschnitts – bestimmt den Ordnernamen (und damit z. B. das Lightroom-Preset).
/// Deckt Alltag, Reisen, Feiern und Hochzeiten ab; Hochzeits-Kategorien greifen nur bei Hochzeitsmerkmalen.
enum EventKind: String, CaseIterable, Identifiable {
    // Hochzeit
    case gettingReady, ceremonyChurch, ceremonyCivil, ceremonyOutdoor, reception, couple
    // Menschen
    case groupPhotos, portraits, kids
    // Feiern & Erlebnisse
    case birthday, christmas, party, concert, sports, dinner
    // Orte & Reisen
    case beach, mountains, winter, city, nature, travel, home, night
    // Sonstiges
    case animals, details, documents, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingReady: "Getting Ready"
        case .ceremonyChurch: "Trauung Kirche"
        case .ceremonyCivil: "Trauung Standesamt"
        case .ceremonyOutdoor: "Freie Trauung"
        case .reception: "Sektempfang"
        case .couple: "Paarshooting"
        case .groupPhotos: "Gruppenfotos"
        case .portraits: "Porträts"
        case .kids: "Kinder & Spielplatz"
        case .birthday: "Geburtstag"
        case .christmas: "Weihnachten"
        case .party: "Party & Feiern"
        case .concert: "Konzert & Bühne"
        case .sports: "Sport"
        case .dinner: "Essen & Trinken"
        case .beach: "Strand & Meer"
        case .mountains: "Berge & Wandern"
        case .winter: "Winter & Schnee"
        case .city: "Stadt & Sightseeing"
        case .nature: "Natur & Landschaft"
        case .travel: "Unterwegs"
        case .home: "Zuhause"
        case .night: "Nacht & Lichter"
        case .animals: "Tiere"
        case .details: "Details"
        case .documents: "Dokumente & Screenshots"
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
        case .couple: "heart.fill"
        case .groupPhotos: "person.3.fill"
        case .portraits: "person.crop.square.fill"
        case .kids: "figure.and.child.holdinghands"
        case .birthday: "birthday.cake.fill"
        case .christmas: "tree.fill"
        case .party: "party.popper.fill"
        case .concert: "music.mic"
        case .sports: "sportscourt.fill"
        case .dinner: "fork.knife"
        case .beach: "beach.umbrella.fill"
        case .mountains: "mountain.2.fill"
        case .winter: "snowflake"
        case .city: "building.2.fill"
        case .nature: "tree.circle.fill"
        case .travel: "airplane"
        case .home: "house.fill"
        case .night: "moon.stars.fill"
        case .animals: "pawprint.fill"
        case .details: "sparkles"
        case .documents: "doc.text.fill"
        case .other: "photo.on.rectangle"
        }
    }

    /// Gewichte für Vision-Labels (Bildklassifikation mit über 1300 Begriffen).
    fileprivate var labelWeights: [String: Double] {
        switch self {
        case .gettingReady:
            ["cosmetic_tool": 3, "bathrobe": 3, "bedroom": 2, "bathroom_room": 2, "bathroom": 1.5, "washbasin": 1.5,
             "high_heel": 2, "closet": 1.5, "bed": 1.5, "jewelry": 1, "wedding_dress": 1.5, "curtain": 0.4]
        case .ceremonyChurch:
            ["stained_glass": 4, "organ_instrument": 4, "belltower": 2, "candlestick": 1.5, "ceremony": 1.5,
             "arch": 1, "dome": 1, "chandelier": 0.6, "auditorium": 0.8, "candle": 0.5]
        case .ceremonyCivil:
            ["ceremony": 1.5, "conference": 1.5, "desk": 1.5, "document": 1.5, "podium": 1.5, "pen": 1,
             "office_supplies": 1, "flag": 1, "interior_room": 0.4, "bouquet": 0.6]
        case .ceremonyOutdoor:
            ["ceremony": 1.5, "pergola": 1.5, "folding_chair": 1.5, "gazebo": 1, "arch": 1,
             "flower_arrangement": 0.8, "garden": 0.8]
        case .reception:
            ["sparkling_wine": 4, "drinking_glass": 2.5, "cocktail": 2, "white_wine": 2, "wine": 1.5, "drink": 1.5,
             "celebration": 1, "crowd": 1, "patio": 0.8, "garden": 0.4]
        case .couple:
            ["bride": 1.5, "groom": 1.5, "wedding_dress": 1, "sunset_sunrise": 1, "lake": 0.6, "forest": 0.6, "park": 0.4]
        case .groupPhotos:
            ["crowd": 0.8, "people": 0.5]
        case .portraits, .other:
            [:]
        case .kids:
            ["playground": 4, "swing_playground": 3, "slide_toy": 3, "seesaw": 3, "sandbox": 2, "toy": 2, "stuffed_animals": 2,
             "baby": 2, "child": 1, "stroller": 2, "high_chair": 2, "crib": 2, "blocks": 2, "trampoline": 2, "sandcastle": 2]
        case .birthday:
            ["birthday_cake": 5, "balloon": 2.5, "cupcake": 1.5, "gift": 2, "candle": 1, "celebration": 1.5, "cake": 1]
        case .christmas:
            ["christmas_tree": 5, "christmas_decoration": 4, "santa_claus": 4, "gingerbread": 2, "candy_cane": 2,
             "wreath": 2, "poinsettia": 2, "mistletoe": 2, "holly": 1.5]
        case .party:
            ["dancing": 3, "disco_ball": 4, "nightclub": 3, "deejay": 3, "celebration": 1.5, "cocktail": 1.5,
             "sparkler": 2.5, "beer": 1.5, "liquor": 1, "costume": 1.5, "crowd": 0.8]
        case .concert:
            ["concert": 4, "singer": 3, "guitar": 2, "drum": 2, "microphone": 2, "orchestra": 3, "theater": 2.5,
             "performance": 2, "spotlight": 1.5, "musical_instrument": 1.5, "piano": 1.5, "entertainer": 1.5]
        case .sports:
            ["sport": 1.5, "soccer": 3, "football": 3, "basketball": 3, "tennis": 3, "cycling": 3, "swimming": 2.5,
             "athletics": 3, "stadium": 2.5, "golf": 3, "volleyball": 3, "skateboarding": 3, "surfing": 3, "workout": 2,
             "equestrian": 3, "ballgames": 2, "gymnastics": 3, "rock_climbing": 2]
        case .dinner:
            ["dining_room": 2.5, "tableware": 2.5, "food": 2, "plate": 2, "restaurant": 2.5, "wedding_cake": 2,
             "fork": 1.5, "dessert": 1.5, "table": 1, "utensil": 1, "wine_bottle": 1, "coffee": 1.5, "pizza": 2,
             "pasta": 2, "sushi": 2, "salad": 1.5, "bread": 1, "meat": 1.5, "ice_cream": 1.5]
        case .beach:
            ["beach": 4, "ocean": 3, "shore": 2.5, "sand": 1.5, "swimsuit": 2.5, "surfboard": 2.5, "sunbathing": 3,
             "palm_tree": 2, "seashell": 2, "pier": 1.5, "sailboat": 1.5, "pool": 2, "water_body": 0.8]
        case .mountains:
            ["mountain": 4, "hiking": 4, "cliff": 2.5, "hill": 2, "trail": 2.5, "canyon": 3, "glacier": 3,
             "rocks": 1.5, "valley": 2, "backpack": 1]
        case .winter:
            ["snow": 4, "skiing": 4, "snowboarding": 4, "ski_equipment": 3, "sled": 3, "snowman": 4,
             "ice_skating": 3, "blizzard": 3, "winter_sport": 3, "frozen": 2, "ice": 1.5]
        case .city:
            ["cityscape": 4, "skyscraper": 3, "street": 2, "building": 1.5, "monument": 3, "castle": 3, "bridge": 2,
             "stained_glass": 2.5, "organ_instrument": 2, "belltower": 2.5, "dome": 2, "arch": 1,
             "museum": 3, "tower": 2, "statue": 2.5, "fountain": 2, "storefront": 2, "alley": 2, "plaza": 2, "ruins": 3]
        case .nature:
            ["forest": 3, "lake": 3, "river": 2.5, "waterfall": 4, "foliage": 1.5, "flower": 2, "garden": 2,
             "sunset_sunrise": 2.5, "tree": 1, "grass": 0.8, "blue_sky": 0.8, "field": 1.5, "vineyard": 2.5, "meadow": 2]
        case .travel:
            ["airplane": 3, "airport": 4, "train": 2.5, "train_station": 3, "car": 1.5, "road": 1.5, "boat": 2,
             "cruise_ship": 3, "luggage": 3, "suitcase": 3, "map": 2, "bus": 2, "motorhome": 3, "tent": 2.5, "camping": 3]
        case .home:
            ["living_room": 3, "kitchen": 3, "kitchen_room": 3, "sofa": 2, "bedroom": 1.5, "interior_room": 0.8,
             "fireplace": 2, "bookshelf": 1.5, "houseplant": 1, "television": 1.5]
        case .night:
            ["night_sky": 4, "fireworks": 4, "aurora": 4, "moon": 3, "lantern": 1.5, "light": 0.8, "celestial_body": 2]
        case .animals:
            ["animal": 2, "dog": 3, "cat": 3, "horse": 3, "bird": 2.5, "zoo": 4, "cow": 3, "sheep": 3, "goat": 3,
             "farm": 2, "puppy": 3, "kitten": 3, "fish": 2, "aquarium": 3, "pig": 3, "rabbit": 3, "duck": 2.5]
        case .details:
            ["flower_arrangement": 2, "bouquet": 2, "decoration": 2, "jewelry": 1.5, "wedding_cake": 1.5,
             "rose": 1, "gift": 1, "vase": 1, "candle": 1, "printed_page": 0.5]
        case .documents:
            ["document": 4, "screenshot": 5, "printed_page": 3, "receipt": 4, "handwriting": 3, "diagram": 3,
             "whiteboard": 3, "chart": 3, "illustrations": 2, "map": 1]
        }
    }

    fileprivate var isWedding: Bool {
        [.gettingReady, .ceremonyChurch, .ceremonyCivil, .ceremonyOutdoor, .reception, .couple].contains(self)
    }
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
        let wedding = ["wedding", "bride", "groom", "wedding_dress", "wedding_cake", "bouquet"]
            .map { Double(analysis.labels[$0] ?? 0) }.reduce(0, +)

        // Gesichter sagen viel über die Art der Aufnahme.
        result[.groupPhotos, default: 0] += faces >= 4 ? 1.6 : faces == 3 ? 0.9 : 0
        result[.couple, default: 0] += faces == 2 ? 0.4 : 0
        result[.portraits, default: 0] += faces == 1 && analysis.category == .portrait ? 0.9 : 0
        result[.details, default: 0] *= faces == 0 ? 1.4 : 0.3
        result[.documents, default: 0] += analysis.isUtility ? 3 : 0
        result[.animals, default: 0] += analysis.hasAnimal ? 1.5 : 0

        // Hochzeits-Kategorien nur, wenn auch Hochzeitsmerkmale (Braut, Brautkleid …) erkannt werden.
        let weddingFactor = min(wedding * 2, 1)
        for kind in EventKind.allCases where kind.isWedding {
            result[kind, default: 0] *= 0.15 + 0.85 * weddingFactor
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
        do {
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
