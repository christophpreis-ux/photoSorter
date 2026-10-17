import Testing
import Foundation
import ImageIO
@testable import PhotoSorter

@Suite("Lightroom: Presets und XMP")
struct LightroomTests {
    private let samplePreset = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
     <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
      <rdf:Description rdf:about=""
        xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        crs:PresetType="Normal"
        crs:UUID="ABC"
        crs:SupportsAmount="True"
        crs:Version="15.0"
        crs:ProcessVersion="11.0"
        crs:Exposure2012="+0.40"
        crs:Contrast2012="-12">
       <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Soft Wedding Light</rdf:li></rdf:Alt></crs:Name>
       <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">Meine Hochzeit</rdf:li></rdf:Alt></crs:Group>
       <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>255, 240</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
      </rdf:Description>
     </rdf:RDF>
    </x:xmpmeta>
    """

    private func parsedSample() throws -> LightroomPreset {
        let document = try XMLDocument(xmlString: samplePreset, options: [])
        return try #require(LightroomPresets.parsePreset(document: document, fallbackName: "x", id: "sample"))
    }

    @Test("Preset-Datei wird gelesen: Name, Gruppe, Einstellungen, Kurven – ohne Preset-Metadaten")
    func parsePreset() throws {
        let preset = try parsedSample()
        #expect(preset.name == "Soft Wedding Light")
        #expect(preset.group == "Meine Hochzeit")
        #expect(preset.attributes["crs:Exposure2012"] == "+0.40")
        #expect(preset.attributes["crs:PresetType"] == nil)
        #expect(preset.attributes["crs:UUID"] == nil)
        #expect(preset.elements.map(\.localName) == ["ToneCurvePV2012"])
    }

    @Test("Profile (Looks) werden nicht als Preset angeboten")
    func profilesAreIgnored() throws {
        let look = samplePreset.replacingOccurrences(of: "crs:PresetType=\"Normal\"", with: "crs:PresetType=\"Look\"")
        #expect(LightroomPresets.parsePreset(document: try XMLDocument(xmlString: look, options: []), fallbackName: "x", id: "l") == nil)
    }

    @Test("Vorschläge: passendes eigenes Preset hat Vorrang, sonst eingebauter Vorschlag")
    func suggestions() throws {
        let own = try parsedSample()
        #expect(LightroomPresets.suggestion(for: .reception, among: [own]).id == "sample")
        #expect(LightroomPresets.suggestion(for: .beach, among: [own]).id == "photosorter.summer")
        #expect(LightroomPresets.suggestion(for: .portraits, among: []).id == "photosorter.portrait")
        // Jede Kategorie hat einen gültigen eingebauten Vorschlag.
        for kind in EventKind.allCases {
            #expect(LightroomPresets.builtIn.contains { $0.id == "photosorter." + kind.builtInPresetKey })
        }
    }

    @Test("XMP-Begleitdatei: Einstellungen werden ergänzt, vorhandene Bewertung bleibt erhalten")
    func sidecarMergesExisting() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("IMG_1.CR3")
        TestSupport.touch(raw)
        try """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/></rdf:RDF></x:xmpmeta>
        """.write(to: root.appendingPathComponent("IMG_1.xmp"), atomically: true, encoding: .utf8)

        let sidecar = try XMPWriter.writeSidecar(for: raw, preset: try parsedSample(), keywords: ["Sektempfang"])
        let text = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(text.contains("xmp:Rating=\"4\""))
        #expect(text.contains("crs:Exposure2012=\"+0.40\""))
        #expect(text.contains("crs:HasSettings=\"True\""))
        #expect(text.contains("ToneCurvePV2012"))
        #expect(text.contains("Sektempfang"))
        #expect(text.contains("PhotoSorter|Sektempfang"))

        // Zweimal anwenden erzeugt keine doppelten Einträge.
        _ = try XMPWriter.writeSidecar(for: raw, preset: try parsedSample(), keywords: ["Sektempfang"])
        let again = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(again.components(separatedBy: "crs:Exposure2012").count == 2)
        #expect(again.components(separatedBy: "<rdf:li>Sektempfang</rdf:li>").count == 2)
    }

    @Test("JPEG: Einstellungen landen verlustfrei in den Metadaten")
    func embedIntoJPEG() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let jpeg = root.appendingPathComponent("IMG_2.jpg")
        TestSupport.writeJPEG(to: jpeg, width: 120, height: 90)
        let sizeBefore = CGImageSourceCreateWithURL(jpeg as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }

        try XMPWriter.embed(into: jpeg, preset: LightroomPresets.builtIn("bw"), keywords: ["Party & Feiern"])

        let source = try #require(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        let metadata = try #require(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        CGImageMetadataRegisterNamespaceForPrefix(metadata as! CGMutableImageMetadata? ?? CGImageMetadataCreateMutable(),
                                                  XMPNamespace.crs as CFString, "crs" as CFString, nil)
        let gray = CGImageMetadataCopyStringValueWithPath(metadata, nil, "crs:ConvertToGrayscale" as CFString) as String?
        #expect(gray == "True")
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(props?[kCGImagePropertyPixelWidth] as? Int == sizeBefore?[kCGImagePropertyPixelWidth] as? Int)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)   // keine Temp-Datei übrig
    }

    @Test("Exporter: RAW → Begleitdatei, JPEG → eingebettet, DNG übersprungen")
    func exporter() throws {
        let root = TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = root.appendingPathComponent("A.NEF"), jpeg = root.appendingPathComponent("A.jpg"), dng = root.appendingPathComponent("B.dng")
        TestSupport.touch(raw)
        TestSupport.touch(dng)
        TestSupport.writeJPEG(to: jpeg, width: 60, height: 40)
        let report = LightroomExporter.apply([
            LightroomItem(files: [jpeg, raw], preset: LightroomPresets.builtIn("natural"), keywords: []),
            LightroomItem(files: [dng], preset: LightroomPresets.builtIn("natural"), keywords: []),
        ]) { _ in }
        #expect(report.sidecars == 1)
        #expect(report.embedded == 1)
        #expect(report.skipped.count == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.xmp").path))
    }
}
