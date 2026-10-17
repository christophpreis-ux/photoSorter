import Testing
import Foundation
import CoreGraphics
@testable import PhotoSorter

@Suite("Bildanalyse und Kombinieren")
struct AnalysisTests {
    @Test("Scharfe Bilder bekommen einen deutlich höheren Schärfewert als unscharfe")
    func sharpnessMeasurement() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sharpURL = root.appendingPathComponent("scharf.jpg")
        let blurryURL = root.appendingPathComponent("unscharf.jpg")
        TestSupport.writeJPEG(to: sharpURL)
        TestSupport.writeJPEG(to: blurryURL, blurRadius: 6)

        let sharp = try #require(ImageAnalyzer.analyze(url: sharpURL, isRaw: false))
        let blurry = try #require(ImageAnalyzer.analyze(url: blurryURL, isRaw: false))
        #expect(sharp.analysis.peakSharpness > blurry.analysis.peakSharpness * 3)
        #expect(sharp.analysis.thumbnailData != nil)
        #expect(sharp.analysis.faces.isEmpty)
        #expect(sharp.analysis.pixelSize == CGSize(width: 800, height: 600))
    }

    @Test("Ausrichtung beim Kombinieren findet Drehung, Skalierung und Verschiebung")
    func similarityTransform() throws {
        let source: [CGPoint] = (0..<30).map { (i: Int) -> CGPoint in
            let x = Double(i % 6) * 13
            let y = Double(i / 6) * 9 + Double(i % 3)
            return CGPoint(x: x, y: y)
        }
        let truth = CGAffineTransform(rotationAngle: 0.2).scaledBy(x: 1.3, y: 1.3)
            .concatenating(CGAffineTransform(translationX: 40, y: -12))
        let target = source.map { $0.applying(truth) }
        let found = try #require(FaceMerger.similarityTransform(from: source, to: target))
        for (point, expected) in zip(source, target) {
            let mapped = point.applying(found)
            #expect(abs(mapped.x - expected.x) < 0.001)
            #expect(abs(mapped.y - expected.y) < 0.001)
        }
    }

    @Test("Kombinier-Vorschlag nur, wenn auf dem besten Foto jemand die Augen zu hat")
    func mergeCandidate() throws {
        let faces = { (left: Double, right: Double) in
            [TestSupport.face(x: 0.2, eyes: left, quality: 0.5), TestSupport.face(x: 0.6, eyes: right, quality: 0.5)]
        }
        let allOpen = [
            TestSupport.photo("A", at: 0, analysis: TestSupport.analysis(faces: faces(0.33, 0.32), sharpness: 900)),
            TestSupport.photo("B", at: 1, analysis: TestSupport.analysis(faces: faces(0.32, 0.33), sharpness: 400)),
        ]
        let scene = TestSupport.scene(allOpen)
        let evaluation = SelectionEngine.evaluate(scene: scene)
        let decisions = SelectionEngine.decide(evaluation, strictness: 0.5, overrides: [:])
        #expect(FaceMerger.candidate(scene: scene, evaluation: evaluation, decisions: decisions) == nil)

        let blink = [
            TestSupport.photo("C", at: 0, analysis: TestSupport.analysis(faces: faces(0.34, 0.06), sharpness: 2000)),
            TestSupport.photo("D", at: 1, analysis: TestSupport.analysis(faces: faces(0.20, 0.33), sharpness: 300)),
        ]
        let blinkScene = TestSupport.scene(blink)
        let blinkEvaluation = SelectionEngine.evaluate(scene: blinkScene)
        let blinkDecisions = SelectionEngine.decide(blinkEvaluation, strictness: 0.5, overrides: [:])
        let candidate = FaceMerger.candidate(scene: blinkScene, evaluation: blinkEvaluation, decisions: blinkDecisions)
        if let candidate {
            #expect(candidate.swaps.allSatisfy { $0.donor.id != candidate.base.id })
            #expect(!candidate.swaps.isEmpty)
        } else {
            // Ist D das beste Foto (alle Augen offen), gibt es zu Recht nichts zu kombinieren.
            #expect(blinkEvaluation.ranking.first == blink[1].id)
        }
    }
}

@Suite("Apple Fotos: Favoriten")
@MainActor
struct FavoriteTests {
    @Test("Favoriten werden immer behalten – auch bei maximaler Strenge und manuellem Aussortieren")
    func favoritesAreAlwaysKept() {
        let photos = [600, 400, 80, 30].enumerated().map { index, sharpness in
            TestSupport.photo("F\(index)", at: Double(index), analysis: TestSupport.analysis(sharpness: Double(sharpness)),
                              favorite: index == 3)
        }
        let favorite = photos[3]
        let model = AppModel()
        model.load(analyzedPhotos: photos, source: .folder(URL(fileURLWithPath: "/tmp")))
        model.strictness = 1

        #expect(model.decisions[favorite.id]?.keep == true)
        #expect(model.decisions[favorite.id]?.isFavorite == true)

        model.setOverride(false, for: favorite)
        model.toggle(favorite)
        #expect(model.decisions[favorite.id]?.keep == true)

        // Nicht-Favoriten lassen sich weiterhin aussortieren.
        #expect(model.decisions[photos[2].id]?.keep == false)
        #expect(model.favoriteCount == 1)
    }
}

@Suite("Oberfläche: Foto-Raster")
struct ThumbnailLayoutTests {
    private let layout = ThumbnailFlowLayout(itemSize: CGSize(width: 100, height: 75), spacing: 8)

    @Test("Unendliche, fehlende oder ungültige Breite führt nicht zum Absturz")
    func nonFiniteWidths() {
        for width: CGFloat? in [nil, .infinity, -.infinity, .nan, 0, -50] {
            let size = layout.size(forCount: 7, proposedWidth: width)
            #expect(size.width.isFinite && size.height.isFinite)
            #expect(size.height > 0)
        }
        #expect(layout.columns(for: .infinity) == 1)
        #expect(layout.columns(for: .nan) == 1)
    }

    @Test("Spalten und Höhe werden korrekt berechnet")
    func normalWidths() {
        #expect(layout.columns(for: 324) == 3)                     // 3 × 100 + 2 × 8 = 316
        #expect(layout.size(forCount: 7, proposedWidth: 324).height == CGFloat(3 * 75 + 2 * 8))
        #expect(layout.size(forCount: 0, proposedWidth: 324).height == 0)
    }
}
