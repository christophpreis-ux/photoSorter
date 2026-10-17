import Testing
import Foundation
@testable import PhotoSorter

@Suite("Auswahl: welche Fotos behalten werden")
struct SelectionEngineTests {
    private func decide(_ photos: [PhotoItem], strictness: Double, overrides: [UUID: Bool] = [:]) -> (SceneEvaluation, [UUID: Decision]) {
        let evaluation = SelectionEngine.evaluate(scene: TestSupport.scene(photos))
        return (evaluation, SelectionEngine.decide(evaluation, strictness: strictness, overrides: overrides))
    }

    private func landscapeSeries() -> [PhotoItem] {
        [500, 320, 90, 40].enumerated().map { index, sharpness in
            TestSupport.photo("L\(index)", at: Double(index), analysis: TestSupport.analysis(sharpness: sharpness))
        }
    }

    @Test("Strenge 0 behält alles")
    func minimumStrictnessKeepsEverything() {
        let (_, decisions) = decide(landscapeSeries(), strictness: 0)
        #expect(decisions.values.allSatisfy { $0.keep })
    }

    @Test("Strenge 1 behält nur das beste Foto einer Serie ohne Gesichter")
    func maximumStrictnessKeepsOnlyBest() {
        let photos = landscapeSeries()
        let (_, decisions) = decide(photos, strictness: 1)
        #expect(decisions.values.filter(\.keep).count == 1)
        #expect(decisions[photos[0].id]?.keep == true)
        #expect(decisions[photos[0].id]?.isBest == true)
    }

    @Test("Höhere Strenge sortiert nie weniger aus")
    func strictnessIsMonotonic() {
        let photos = landscapeSeries()
        var previous = Int.max
        for strictness in stride(from: 0.0, through: 1.0, by: 0.1) {
            let kept = decide(photos, strictness: strictness).1.values.filter(\.keep).count
            #expect(kept <= previous)
            previous = kept
        }
    }

    @Test("Unscharfe Fotos werden markiert")
    func blurryPhotosAreFlagged() {
        let photos = landscapeSeries()
        let (_, decisions) = decide(photos, strictness: 0.5)
        #expect(decisions[photos[3].id]?.issues.contains(.blurry) == true)
        #expect(decisions[photos[3].id]?.keep == false)
    }

    @Test("Ein gutes Einzelfoto wird behalten")
    func singlePhotoIsKept() {
        let photo = TestSupport.photo("S", at: 0, analysis: TestSupport.analysis(sharpness: 400))
        let (_, decisions) = decide([photo], strictness: 0.8)
        #expect(decisions[photo.id]?.keep == true)
    }

    @Test("Geschlossene Augen werden erkannt und aussortiert, wenn es Alternativen gibt")
    func closedEyesAreRejected() {
        let open1 = TestSupport.photo("P1", at: 0, analysis: TestSupport.analysis(faces: [TestSupport.face(x: 0.4, eyes: 0.33)]))
        let closed = TestSupport.photo("P2", at: 1, analysis: TestSupport.analysis(faces: [TestSupport.face(x: 0.41, eyes: 0.07)]))
        let open2 = TestSupport.photo("P3", at: 2, analysis: TestSupport.analysis(faces: [TestSupport.face(x: 0.4, eyes: 0.31)]))
        let (_, decisions) = decide([open1, closed, open2], strictness: 0.5)
        #expect(decisions[closed.id]?.issues.contains(.eyesClosed) == true)
        #expect(decisions[closed.id]?.keep == false)
    }

    @Test("Gruppenfoto: Jede Person ist auf mindestens einem behaltenen Foto mit offenen Augen")
    func groupPhotoCoversEveryPerson() {
        // A: schärfer, aber Person rechts blinzelt. B: etwas weicher, beide Augen offen. C: links blinzelt.
        let a = TestSupport.photo("A", at: 0, analysis: TestSupport.analysis(
            faces: [TestSupport.face(x: 0.2, eyes: 0.34, quality: 0.6), TestSupport.face(x: 0.6, eyes: 0.07, quality: 0.3)],
            sharpness: 900))
        let b = TestSupport.photo("B", at: 1, analysis: TestSupport.analysis(
            faces: [TestSupport.face(x: 0.21, eyes: 0.30, quality: 0.45), TestSupport.face(x: 0.61, eyes: 0.33, quality: 0.55)],
            sharpness: 450))
        let c = TestSupport.photo("C", at: 2, analysis: TestSupport.analysis(
            faces: [TestSupport.face(x: 0.2, eyes: 0.06, quality: 0.3), TestSupport.face(x: 0.6, eyes: 0.32, quality: 0.5)],
            sharpness: 800))

        for strictness in [0.3, 0.6, 1.0] {
            let (evaluation, decisions) = decide([a, b, c], strictness: strictness)
            let people = evaluation.tracks.filter(\.isSignificant)
            #expect(people.count == 2)
            for person in people {
                let covered = person.goodPhotos.contains { decisions[$0]?.keep == true }
                #expect(covered, "Person \(person.id + 1) ohne gute Version bei Strenge \(strictness)")
            }
        }
    }

    @Test("Manuelle Entscheidung hat Vorrang")
    func manualOverrideWins() {
        let photos = landscapeSeries()
        let (_, decisions) = decide(photos, strictness: 1, overrides: [photos[3].id: true, photos[0].id: false])
        #expect(decisions[photos[3].id]?.keep == true)
        #expect(decisions[photos[3].id]?.isManual == true)
        #expect(decisions[photos[0].id]?.keep == false)
    }
}
