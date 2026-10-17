import Testing
import Foundation
@testable import PhotoSorter

@Suite("Szenen und Abschnitte")
struct GroupingAndEventTests {
    @Test("Serienbilder werden über die Zeit gruppiert")
    func burstGrouping() {
        let photos = [0, 1, 2.5, 20, 21].enumerated().map { index, seconds in
            TestSupport.photo("B\(index)", at: seconds, analysis: TestSupport.analysis())
        }
        let groups = SceneGrouper.group(photos.shuffled(), settings: GroupingSettings())
        #expect(groups.map(\.count) == [3, 2])
        #expect(groups[0].map(\.baseName) == ["B0", "B1", "B2"])
    }

    private func photos(_ labels: [String: Float], count: Int, start: TimeInterval, faces: Int = 0) -> [PhotoItem] {
        (0..<count).map { index in
            let faceInfos = (0..<faces).map { TestSupport.face(x: 0.1 + CGFloat($0) * 0.2) }
            return TestSupport.photo("E\(start)-\(index)", at: start + Double(index) * 5,
                                     analysis: TestSupport.analysis(faces: faceInfos, labels: labels))
        }
    }

    @Test("Allgemeine Kategorien werden erkannt", arguments: [
        (["christmas_tree": 0.9, "christmas_decoration": 0.6], EventKind.christmas),
        (["beach": 0.9, "ocean": 0.7, "sand": 0.5], .beach),
        (["mountain": 0.9, "hiking": 0.6], .mountains),
        (["snow": 0.9, "skiing": 0.7], .winter),
        (["birthday_cake": 0.9, "balloon": 0.5], .birthday),
        (["playground": 0.9, "swing_playground": 0.5], .kids),
        (["concert": 0.9, "singer": 0.6], .concert),
        (["cityscape": 0.8, "skyscraper": 0.6], .city),
        (["dog": 0.9, "animal": 0.8], .animals),
        (["food": 0.8, "plate": 0.7, "tableware": 0.6], .dinner),
    ])
    func generalCategories(labels: [String: Float], expected: EventKind) {
        #expect(EventDetector.kind(for: photos(labels, count: 5, start: 0)) == expected)
    }

    @Test("Hochzeits-Kategorien nur mit Hochzeitsmerkmalen")
    func weddingNeedsWeddingSignals() {
        let church = ["stained_glass": 0.8, "organ_instrument": 0.6, "ceremony": 0.5] as [String: Float]
        var wedding = church
        wedding["bride"] = 0.6
        wedding["wedding_dress"] = 0.5
        #expect(EventDetector.kind(for: photos(wedding, count: 5, start: 0)) == .ceremonyChurch)
        #expect(EventDetector.kind(for: photos(church, count: 5, start: 0)) != .ceremonyChurch)
    }

    @Test("Viele Gesichter ergeben Gruppenfotos")
    func manyFacesAreGroupPhotos() {
        #expect(EventDetector.kind(for: photos([:], count: 5, start: 0, faces: 5)) == .groupPhotos)
    }

    @Test("Lange Pause trennt Abschnitte, gleiche Art mit kurzer Pause bleibt zusammen")
    func chapterDetection() {
        let settings = GroupingSettings()
        let beach1 = photos(["beach": 0.9, "ocean": 0.7], count: 15, start: 0)
        let beach2 = photos(["beach": 0.9, "ocean": 0.7], count: 15, start: 400)     // kurze Pause → gleicher Abschnitt
        let party = photos(["dancing": 0.9, "disco_ball": 0.7], count: 15, start: 7200) // 2 h später
        let scenes = SceneGrouper.group(beach1 + beach2 + party, settings: settings)
            .enumerated().map { PhotoScene(index: $0.offset + 1, photos: $0.element) }
        let chapters = EventDetector.detect(scenes: scenes, settings: settings)
        #expect(chapters.map(\.kind) == [.beach, .party])
        #expect(chapters.first?.name == "Strand & Meer")
    }

    @Test("Ordnernamen sind nummeriert und dateisystemtauglich")
    func folderNames() {
        #expect(EventDetector.folderName(index: 3, name: "Trauung/Kirche: 14 Uhr") == "03 Trauung-Kirche. 14 Uhr")
        #expect(EventDetector.folderName(index: 12, name: "  ") == "12 Abschnitt")
    }
}
