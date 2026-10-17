import Foundation

/// Findet alle Fotos in einem Ordner (nicht rekursiv) und fasst RAW/JPEG/XMP mit gleichem Namen zusammen.
enum PhotoScanner {
    static let rawExtensions: Set<String> = [
        "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "dng", "raf", "orf",
        "rw2", "pef", "srw", "3fr", "iiq", "erf", "mos", "x3f", "rwl", "raw",
    ]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp", "avif"]
    static let sidecarExtensions: Set<String> = ["xmp", "aae"]

    /// Liest den Ordner inklusive Unterordnern (z. B. bereits sortierte Abschnitts-Ordner) – „Terminiert“/„Aussortiert“ werden übersprungen.
    static func scan(folder: URL) throws -> [PhotoItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .creationDateKey, .fileSizeKey]
        _ = try FileManager.default.contentsOfDirectory(atPath: folder.path) // wirft, wenn der Ordner nicht lesbar ist
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if FileOrganizer.skippedFolderNames.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if values?.isRegularFile == true { files.append(url) }
        }
        // RAW/JPEG/XMP gehören zusammen, wenn sie im selben Ordner denselben Namen haben.
        let byBase = Dictionary(grouping: files) {
            $0.deletingLastPathComponent().path + "/" + $0.deletingPathExtension().lastPathComponent
        }

        var items: [PhotoItem] = []
        for (_, group) in byBase {
            guard let base = group.first?.deletingPathExtension().lastPathComponent else { continue }
            let ext = { (url: URL) in url.pathExtension.lowercased() }
            let images = group.filter { imageExtensions.contains(ext($0)) }
            let raws = group.filter { rawExtensions.contains(ext($0)) }
            guard let primary = images.sorted(by: { rank($0) < rank($1) }).first ?? raws.first else { continue }
            let sidecars = group.filter { sidecarExtensions.contains(ext($0)) }
            let all = (images + raws + sidecars).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let date = (try? primary.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let item = PhotoItem(baseName: base, files: all, primaryURL: primary, captureDate: date)
            item.byteSize = all.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            items.append(item)
        }
        return items.sorted { $0.baseName.localizedStandardCompare($1.baseName) == .orderedAscending }
    }

    /// JPEG/HEIC bevorzugt für die Analyse – schneller als RAW-Dekodierung.
    private static func rank(_ url: URL) -> Int {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": 0
        case "heic", "heif": 1
        default: 2
        }
    }
}
