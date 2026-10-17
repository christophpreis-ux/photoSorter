import Testing
import Foundation
@testable import PhotoSorter

@Suite("Dateien einlesen, sortieren und rückgängig machen")
struct FileTests {
    private let fm = FileManager.default

    private func exists(_ root: URL, _ path: String) -> Bool {
        fm.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    @Test("Scanner: RAW+JPEG+XMP als ein Foto, Unterordner ja, „Aussortiert“ nein")
    func scanner() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? fm.removeItem(at: root) }
        TestSupport.writeJPEG(to: root.appendingPathComponent("IMG_1.jpg"), width: 40, height: 30)
        TestSupport.touch(root.appendingPathComponent("IMG_1.CR3"))
        TestSupport.touch(root.appendingPathComponent("IMG_1.xmp"))
        TestSupport.touch(root.appendingPathComponent("IMG_2.NEF"))
        TestSupport.writeJPEG(to: root.appendingPathComponent("01 Abschnitt/IMG_3.jpg"), width: 40, height: 30)
        TestSupport.writeJPEG(to: root.appendingPathComponent("Aussortiert/IMG_4.jpg"), width: 40, height: 30)
        TestSupport.touch(root.appendingPathComponent("notizen.txt"))
        TestSupport.touch(root.appendingPathComponent(".versteckt.jpg"))

        let items = try PhotoScanner.scan(folder: root)
        #expect(items.map(\.baseName).sorted() == ["IMG_1", "IMG_2", "IMG_3"])
        let first = try #require(items.first { $0.baseName == "IMG_1" })
        #expect(first.files.count == 3)
        #expect(first.primaryURL.pathExtension == "jpg")   // JPEG wird für die Analyse bevorzugt
        #expect(first.hasRaw)
        #expect(items.first { $0.baseName == "IMG_2" }?.isRawPrimary == true)
    }

    @Test("Sortieren verschiebt, benennt um und lässt sich vollständig rückgängig machen")
    func applyAndUndo() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? fm.removeItem(at: root) }
        TestSupport.touch(root.appendingPathComponent("IMG_1.jpg"))
        TestSupport.touch(root.appendingPathComponent("IMG_1.cr2"))
        TestSupport.touch(root.appendingPathComponent("IMG_2.jpg"))
        TestSupport.touch(root.appendingPathComponent("IMG_3.jpg"))
        TestSupport.touch(root.appendingPathComponent("Aussortiert/IMG_2.jpg"))   // Namenskonflikt

        let items = try PhotoScanner.scan(folder: root)
        let item = { (name: String) in items.first { $0.baseName == name }! }
        let result = try FileOrganizer.apply(
            rejected: [item("IMG_2")],
            kept: [KeptPlacement(item: item("IMG_1"), folder: "01 Gruppenfotos", category: .group),
                   KeptPlacement(item: item("IMG_3"), folder: nil, category: .other)],
            extraFiles: [], in: root, renameKept: true)

        #expect(exists(root, "01 Gruppenfotos/Gruppenfoto_IMG_1.jpg"))
        #expect(exists(root, "01 Gruppenfotos/Gruppenfoto_IMG_1.cr2"))   // RAW bleibt beim JPEG
        #expect(exists(root, "Aussortiert/IMG_2_1.jpg"))                 // kein Überschreiben
        #expect(exists(root, "Aussortiert/IMG_2.jpg"))
        #expect(exists(root, "Motiv_IMG_3.jpg"))                         // ohne Ordner: bleibt liegen
        #expect(result.rejectedPhotos == 1)
        #expect(result.sortedPhotos == 1)

        let errors = FileOrganizer.undo(result.moves, createdFolders: result.createdFolders)
        #expect(errors.isEmpty)
        for name in ["IMG_1.jpg", "IMG_1.cr2", "IMG_2.jpg", "IMG_3.jpg", "Aussortiert/IMG_2.jpg"] {
            #expect(exists(root, name), "\(name) fehlt nach Rückgängig")
        }
        #expect(!exists(root, "01 Gruppenfotos"))   // angelegter Ordner wieder entfernt
    }

    @Test("Es wird nie etwas gelöscht")
    func nothingIsDeleted() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? fm.removeItem(at: root) }
        for index in 1...5 { TestSupport.touch(root.appendingPathComponent("IMG_\(index).jpg")) }
        let items = try PhotoScanner.scan(folder: root)
        _ = try FileOrganizer.apply(rejected: Array(items.prefix(3)),
                                    kept: items.suffix(2).map { KeptPlacement(item: $0, folder: "02 Rest", category: .other) },
                                    extraFiles: [], in: root, renameKept: false)
        let all = fm.enumerator(atPath: root.path)?.allObjects.compactMap { $0 as? String }.filter { $0.hasSuffix(".jpg") } ?? []
        #expect(all.count == 5)
    }
}
