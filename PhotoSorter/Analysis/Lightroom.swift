import Foundation
import AppKit
import ImageIO

// MARK: - Presets

/// Ein Lightroom-Entwicklungs-Preset (aus Lightroom/Camera Raw oder ein eingebauter Vorschlag von PhotoSorter).
final class LightroomPreset: Identifiable, Hashable, @unchecked Sendable {
    let id: String
    let name: String
    let group: String
    let isBuiltIn: Bool
    /// Einfache Einstellungen, z. B. "crs:Exposure2012" → "+0.30".
    let attributes: [String: String]
    /// Komplexe Einstellungen (Gradationskurven, Masken …) als XML-Elemente.
    let elements: [XMLElement]

    init(id: String, name: String, group: String, isBuiltIn: Bool, attributes: [String: String], elements: [XMLElement] = []) {
        self.id = id
        self.name = name
        self.group = group
        self.isBuiltIn = isBuiltIn
        self.attributes = attributes
        self.elements = elements
    }

    static func == (lhs: LightroomPreset, rhs: LightroomPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum XMPNamespace {
    static let x = "adobe:ns:meta/"
    static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let crs = "http://ns.adobe.com/camera-raw-settings/1.0/"
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let lr = "http://ns.adobe.com/lightroom/1.0/"
}

enum LightroomPresets {
    /// Orte, an denen Lightroom Classic, Lightroom und Camera Raw ihre Presets ablegen.
    static var presetFolders: [URL] {
        [URL.applicationSupportDirectory.appendingPathComponent("Adobe/CameraRaw/Settings", isDirectory: true),
         URL(fileURLWithPath: "/Library/Application Support/Adobe/CameraRaw/Settings", isDirectory: true)]
    }

    static var installFolder: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Adobe/CameraRaw/Settings/PhotoSorter", isDirectory: true)
    }

    /// Alle installierten Entwicklungs-Presets (ohne Profile).
    static func installed() -> [LightroomPreset] {
        var presets: [LightroomPreset] = []
        for folder in presetFolders {
            guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "xmp" {
                if let preset = parsePreset(at: url) { presets.append(preset) }
            }
        }
        // Eigene, installierte PhotoSorter-Vorschläge nicht doppelt anzeigen.
        let builtInNames = Set(builtIn.map(\.name))
        return presets.filter { !($0.group == "PhotoSorter" && builtInNames.contains($0.name)) }
            .sorted { ($0.group, $0.name) < ($1.group, $1.name) }
    }

    private static let presetMetaKeys: Set<String> = [
        "PresetType", "Cluster", "UUID", "SupportsAmount", "SupportsAmount2", "SupportsColor", "SupportsMonochrome",
        "SupportsHighDynamicRange", "SupportsNormalDynamicRange", "SupportsSceneReferred", "SupportsOutputReferred",
        "RequiresRGBTables", "CameraModelRestriction", "Copyright", "ContactInfo", "ShowInPresets", "ShowInQuickActions",
    ]
    private static let presetMetaElements: Set<String> = ["Name", "ShortName", "SortName", "Group", "Description", "Cluster"]

    static func parsePreset(at url: URL) -> LightroomPreset? {
        guard let document = try? XMLDocument(contentsOf: url, options: []) else { return nil }
        return parsePreset(document: document, fallbackName: url.deletingPathExtension().lastPathComponent, id: url.path)
    }

    static func parsePreset(document: XMLDocument, fallbackName: String, id: String) -> LightroomPreset? {
        guard let description = (try? document.nodes(forXPath: "//*[local-name()='Description']"))?.first as? XMLElement else { return nil }
        var attributes: [String: String] = [:]
        for attribute in description.attributes ?? [] {
            guard attribute.uri == XMPNamespace.crs || attribute.name?.hasPrefix("crs:") == true,
                  let local = attribute.localName, let value = attribute.stringValue else { continue }
            attributes[local] = value
        }
        // Nur Entwicklungs-Presets – keine Profile ("Look") oder sonstige Vorgaben.
        if let type = attributes["PresetType"], type != "Normal" { return nil }

        func altText(_ name: String) -> String? {
            let element = description.elements(forLocalName: name, uri: XMPNamespace.crs).first
            let li = (try? element?.nodes(forXPath: ".//*[local-name()='li']"))?.first
            let text = (li ?? element)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }

        var elements: [XMLElement] = []
        for child in description.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            guard child.uri == XMPNamespace.crs, let local = child.localName, !presetMetaElements.contains(local) else { continue }
            if child.children?.contains(where: { $0.kind == .element }) == true {
                elements.append(child.copy() as! XMLElement)
            } else if let value = child.stringValue {
                attributes[local] = value   // einfache Eigenschaft als Element geschrieben
            }
        }
        let settings = attributes.filter { !presetMetaKeys.contains($0.key) }
        let hasSettings = settings.keys.contains { $0 != "Version" && $0 != "ProcessVersion" } || !elements.isEmpty
        guard hasSettings else { return nil }
        return LightroomPreset(id: id, name: altText("Name") ?? fallbackName, group: altText("Group") ?? "Eigene Presets",
                               isBuiltIn: false, attributes: settings.reduce(into: [:]) { $0["crs:" + $1.key] = $1.value },
                               elements: elements)
    }

    // MARK: Eingebaute Vorschläge

    static let builtIn: [LightroomPreset] = [
        make("natural", "Natürlich & Klar", ["Contrast2012": "+10", "Highlights2012": "-20", "Shadows2012": "+15",
             "Whites2012": "+5", "Blacks2012": "-5", "Clarity2012": "+5", "Texture": "+5", "Vibrance": "+10"]),
        make("wedding", "Hochzeit Hell & Weich", ["Exposure2012": "+0.25", "Contrast2012": "-10", "Highlights2012": "-35",
             "Shadows2012": "+25", "Clarity2012": "-5", "Texture": "-5", "Vibrance": "+5", "Saturation": "-5",
             "ColorGradeShadowHue": "35", "ColorGradeShadowSat": "8", "ColorGradeHighlightHue": "45",
             "ColorGradeHighlightSat": "6", "ColorGradeBlending": "50"]),
        make("portrait", "Porträt Sanfte Haut", ["Exposure2012": "+0.10", "Contrast2012": "-5", "Highlights2012": "-25",
             "Shadows2012": "+15", "Clarity2012": "-10", "Texture": "-15", "Vibrance": "+5", "Saturation": "-5"]),
        make("landscape", "Landschaft Lebendig", ["Contrast2012": "+15", "Highlights2012": "-40", "Shadows2012": "+30",
             "Whites2012": "+10", "Blacks2012": "-10", "Clarity2012": "+15", "Texture": "+15", "Dehaze": "+10",
             "Vibrance": "+25"]),
        make("summer", "Sommer & Strand", ["Exposure2012": "+0.15", "Highlights2012": "-30", "Shadows2012": "+20",
             "Vibrance": "+20", "Saturation": "+5", "ColorGradeHighlightHue": "50", "ColorGradeHighlightSat": "10",
             "ColorGradeBlending": "50"]),
        make("winter", "Winter Kühl & Klar", ["Exposure2012": "+0.20", "Highlights2012": "-40", "Whites2012": "+15",
             "Vibrance": "+5", "Saturation": "-5", "ColorGradeShadowHue": "215", "ColorGradeShadowSat": "10",
             "ColorGradeBlending": "50"]),
        make("night", "Nacht & Party", ["Exposure2012": "+0.30", "Contrast2012": "+15", "Highlights2012": "-30",
             "Shadows2012": "+35", "Blacks2012": "-15", "Clarity2012": "+10", "Dehaze": "+5", "Vibrance": "+10",
             "LuminanceSmoothing": "25"]),
        make("food", "Essen Appetitlich", ["Exposure2012": "+0.15", "Contrast2012": "+10", "Shadows2012": "+15",
             "Clarity2012": "+5", "Texture": "+10", "Vibrance": "+20"]),
        make("cozy", "Warm & Gemütlich", ["Exposure2012": "+0.10", "Contrast2012": "+5", "Highlights2012": "-20",
             "Shadows2012": "+20", "Vibrance": "+10", "ColorGradeMidtoneHue": "40", "ColorGradeMidtoneSat": "10",
             "ColorGradeBlending": "50"]),
        make("bw", "Schwarzweiß Klassisch", ["ConvertToGrayscale": "True", "Contrast2012": "+25", "Clarity2012": "+15",
             "Blacks2012": "-15", "GrainAmount": "15", "GrainSize": "25", "GrainFrequency": "50"]),
        make("document", "Dokument Klar", ["Contrast2012": "+30", "Whites2012": "+30", "Blacks2012": "-20",
             "Saturation": "-30", "Clarity2012": "+20"]),
    ]

    private static func make(_ key: String, _ name: String, _ settings: [String: String]) -> LightroomPreset {
        var attributes = ["crs:ProcessVersion": "11.0", "crs:WhiteBalance": "As Shot"]
        for (key, value) in settings { attributes["crs:" + key] = value }
        return LightroomPreset(id: "photosorter." + key, name: name, group: "PhotoSorter-Vorschläge", isBuiltIn: true,
                               attributes: attributes)
    }

    static func builtIn(_ key: String) -> LightroomPreset { builtIn.first { $0.id == "photosorter." + key }! }

    /// Schlägt das passendste Preset für eine Kategorie vor – eigene Presets mit passendem Namen haben Vorrang.
    static func suggestion(for kind: EventKind, among presets: [LightroomPreset]) -> LightroomPreset {
        let keywords = kind.presetKeywords
        let scored = presets.filter { !$0.isBuiltIn }.map { preset -> (LightroomPreset, Int) in
            let text = (preset.name + " " + preset.group).lowercased()
            return (preset, keywords.filter { text.contains($0) }.count)
        }
        if let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
        return builtIn(kind.builtInPresetKey)
    }

    /// Installiert die Vorschläge als echte Presets, damit sie auch in Lightroom selbst auswählbar sind.
    static func installBuiltIns() throws -> URL {
        let folder = installFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for preset in builtIn {
            var lines = ""
            for (key, value) in preset.attributes.sorted(by: { $0.key < $1.key }) { lines += "\n    \(key)=\"\(value)\"" }
            let xml = """
            <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="PhotoSorter">
             <rdf:RDF xmlns:rdf="\(XMPNamespace.rdf)">
              <rdf:Description rdf:about=""
                xmlns:crs="\(XMPNamespace.crs)"
                crs:PresetType="Normal"
                crs:Cluster=""
                crs:UUID="\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                crs:SupportsAmount="False"
                crs:SupportsColor="True"
                crs:SupportsMonochrome="True"
                crs:SupportsHighDynamicRange="True"
                crs:SupportsNormalDynamicRange="True"
                crs:SupportsSceneReferred="True"
                crs:SupportsOutputReferred="True"
                crs:Version="15.0"\(lines)>
               <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">\(preset.name)</rdf:li></rdf:Alt></crs:Name>
               <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">PhotoSorter</rdf:li></rdf:Alt></crs:Group>
              </rdf:Description>
             </rdf:RDF>
            </x:xmpmeta>
            """
            try xml.write(to: folder.appendingPathComponent("PhotoSorter – \(preset.name).xmp"), atomically: true, encoding: .utf8)
        }
        return folder
    }
}

extension EventKind {
    /// Begriffe, nach denen in den Namen eigener Presets gesucht wird.
    var presetKeywords: [String] {
        switch self {
        case .gettingReady, .ceremonyChurch, .ceremonyCivil, .ceremonyOutdoor, .reception:
            ["wedding", "hochzeit", "bride", "braut", "airy", "soft", "pastel", "light"]
        case .couple: ["couple", "paar", "wedding", "hochzeit", "romantic", "golden", "warm"]
        case .portraits, .kids: ["portrait", "porträt", "skin", "haut", "soft", "people"]
        case .groupPhotos: ["group", "gruppe", "natural", "natürlich", "clean", "people"]
        case .beach: ["beach", "strand", "summer", "sommer", "sun", "vivid", "travel"]
        case .mountains, .nature: ["landscape", "landschaft", "nature", "natur", "outdoor", "vivid", "hdr"]
        case .winter: ["winter", "snow", "schnee", "cool", "kalt", "cold"]
        case .city, .travel: ["urban", "city", "stadt", "street", "travel", "reise", "architecture"]
        case .dinner: ["food", "essen", "restaurant"]
        case .party, .concert, .night, .birthday: ["night", "nacht", "party", "event", "concert", "low light", "club"]
        case .christmas, .home: ["christmas", "weihnacht", "cozy", "gemütlich", "warm", "indoor"]
        case .sports: ["sport", "action", "punch"]
        case .animals: ["animal", "pet", "tier", "wildlife"]
        case .documents: ["document", "scan", "dokument"]
        case .details, .other: ["natural", "natürlich", "clean", "neutral", "standard"]
        }
    }

    var builtInPresetKey: String {
        switch self {
        case .gettingReady, .ceremonyChurch, .ceremonyCivil, .ceremonyOutdoor, .reception, .couple: "wedding"
        case .portraits, .kids: "portrait"
        case .beach: "summer"
        case .mountains, .nature, .city, .travel: "landscape"
        case .winter: "winter"
        case .party, .concert, .night, .birthday: "night"
        case .dinner: "food"
        case .christmas, .home: "cozy"
        case .documents: "document"
        case .groupPhotos, .sports, .animals, .details, .other: "natural"
        }
    }
}

// MARK: - XMP schreiben

enum XMPWriter {
    private static let skeleton = """
    <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="PhotoSorter">
     <rdf:RDF xmlns:rdf="\(XMPNamespace.rdf)">
      <rdf:Description rdf:about="" xmlns:crs="\(XMPNamespace.crs)" xmlns:dc="\(XMPNamespace.dc)" xmlns:lr="\(XMPNamespace.lr)"/>
     </rdf:RDF>
    </x:xmpmeta>
    """

    /// Baut ein XMP-Dokument mit Preset-Einstellungen und Stichwörtern – auf Basis einer vorhandenen Begleitdatei,
    /// damit Bewertungen und andere Metadaten erhalten bleiben.
    static func document(mergingInto existing: Data?, preset: LightroomPreset?, keywords: [String]) throws -> XMLDocument {
        let document = try existing.flatMap { try? XMLDocument(data: $0, options: []) } ?? XMLDocument(xmlString: skeleton, options: [])
        guard let description = (try document.nodes(forXPath: "//*[local-name()='Description']")).first as? XMLElement else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for (prefix, uri) in [("crs", XMPNamespace.crs), ("dc", XMPNamespace.dc), ("lr", XMPNamespace.lr)]
        where description.namespace(forPrefix: prefix) == nil {
            description.addNamespace(XMLNode.namespace(withName: prefix, stringValue: uri) as! XMLNode)
        }

        if let preset {
            for (name, value) in preset.attributes {
                description.removeAttribute(forName: name)
                description.elements(forLocalName: String(name.dropFirst(4)), uri: XMPNamespace.crs).forEach { $0.detach() }
                description.addAttribute(XMLNode.attribute(withName: name, uri: XMPNamespace.crs, stringValue: value) as! XMLNode)
            }
            for element in preset.elements {
                if let local = element.localName {
                    description.elements(forLocalName: local, uri: XMPNamespace.crs).forEach { $0.detach() }
                    description.removeAttribute(forName: "crs:" + local)
                }
                description.addChild(element.copy() as! XMLElement)
            }
            for (name, value) in ["crs:HasSettings": "True", "crs:AlreadyApplied": "False"] {
                description.removeAttribute(forName: name)
                description.addAttribute(XMLNode.attribute(withName: name, uri: XMPNamespace.crs, stringValue: value) as! XMLNode)
            }
        }

        if !keywords.isEmpty {
            addToBag(description, name: "subject", uri: XMPNamespace.dc, prefix: "dc", values: keywords)
            addToBag(description, name: "hierarchicalSubject", uri: XMPNamespace.lr, prefix: "lr",
                     values: keywords.map { "PhotoSorter|" + $0 })
        }
        return document
    }

    private static func addToBag(_ description: XMLElement, name: String, uri: String, prefix: String, values: [String]) {
        let container = description.elements(forLocalName: name, uri: uri).first ?? {
            let element = XMLElement(name: "\(prefix):\(name)", uri: uri)
            description.addChild(element)
            return element
        }()
        let bag = container.elements(forLocalName: "Bag", uri: XMPNamespace.rdf).first ?? {
            let element = XMLElement(name: "rdf:Bag", uri: XMPNamespace.rdf)
            container.addChild(element)
            return element
        }()
        let existing = Set(bag.elements(forLocalName: "li", uri: XMPNamespace.rdf).compactMap(\.stringValue))
        for value in values where !existing.contains(value) {
            bag.addChild(XMLElement(name: "rdf:li", uri: XMPNamespace.rdf).withValue(value))
        }
    }

    /// RAW: Einstellungen als Begleitdatei (IMG_1234.xmp) – Lightroom liest sie beim Import.
    static func writeSidecar(for rawURL: URL, preset: LightroomPreset?, keywords: [String]) throws -> URL {
        let sidecar = rawURL.deletingPathExtension().appendingPathExtension("xmp")
        let existing = try? Data(contentsOf: sidecar)
        let document = try document(mergingInto: existing, preset: preset, keywords: keywords)
        try document.xmlData(options: [.nodePrettyPrint]).write(to: sidecar, options: .atomic)
        return sidecar
    }

    /// JPEG/HEIC/TIFF: Einstellungen verlustfrei in die Metadaten der Datei schreiben (Bilddaten bleiben unverändert).
    static func embed(into imageURL: URL, preset: LightroomPreset?, keywords: [String]) throws {
        let data = try document(mergingInto: nil, preset: preset, keywords: keywords).xmlData()
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let metadata = CGImageMetadataCreateFromXMPData(data as CFData) else { throw CocoaError(.fileReadCorruptFile) }
        let temp = imageURL.deletingLastPathComponent().appendingPathComponent(".photosorter-\(UUID().uuidString).\(imageURL.pathExtension)")
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        let options = [kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true] as CFDictionary
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options, &error) else {
            try? FileManager.default.removeItem(at: temp)
            throw error?.takeRetainedValue() ?? CocoaError(.fileWriteUnknown)
        }
        _ = try FileManager.default.replaceItemAt(imageURL, withItemAt: temp)
    }
}

private extension XMLElement {
    func withValue(_ value: String) -> XMLElement {
        stringValue = value
        return self
    }
}

// MARK: - Übertragen

struct LightroomItem {
    let files: [URL]
    let preset: LightroomPreset?
    let keywords: [String]
}

struct LightroomReport {
    var sidecars = 0
    var embedded = 0
    var skipped: [String] = []
    var photos = 0
}

enum LightroomExporter {
    /// Schreibt die Einstellungen für alle Fotos. RAW → Begleitdatei, JPEG/HEIC/TIFF/PNG → eingebettet, DNG wird übersprungen.
    static func apply(_ items: [LightroomItem], progress: @Sendable (Int) -> Void) -> LightroomReport {
        var report = LightroomReport()
        for (index, item) in items.enumerated() {
            report.photos += 1
            for file in item.files {
                let ext = file.pathExtension.lowercased()
                do {
                    if ext == "dng" {
                        report.skipped.append("\(file.lastPathComponent) (DNG – bitte in Lightroom zuweisen)")
                    } else if PhotoScanner.rawExtensions.contains(ext) {
                        _ = try XMPWriter.writeSidecar(for: file, preset: item.preset, keywords: item.keywords)
                        report.sidecars += 1
                    } else if PhotoScanner.imageExtensions.contains(ext) {
                        try XMPWriter.embed(into: file, preset: item.preset, keywords: item.keywords)
                        report.embedded += 1
                    }
                } catch {
                    report.skipped.append("\(file.lastPathComponent) (\(error.localizedDescription))")
                }
            }
            progress(index + 1)
        }
        return report
    }
}

enum LightroomApp {
    static let bundleIdentifiers = ["com.adobe.LightroomClassicCC7", "com.adobe.lightroomCC"]

    static var installed: (name: String, url: URL)? {
        for id in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return (FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), url)
            }
        }
        return nil
    }

    /// Öffnet die Fotos in Lightroom – Lightroom zeigt dann den Import-Dialog mit genau diesen Ordnern/Dateien.
    static func open(_ urls: [URL]) {
        guard let app = installed, !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}
