import Foundation

/// Findet alle Fotos in einem Ordner (nicht rekursiv) und fasst RAW/JPEG/XMP mit gleichem Namen zusammen.
enum PhotoScanner {
    static let rawExtensions: Set<String> = [
        "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "dng", "raf", "orf",
        "rw2", "pef", "srw", "3fr", "iiq", "erf", "mos", "x3f", "rwl", "raw",
    ]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp", "avif"]
    static let sidecarExtensions: Set<String> = ["xmp", "aae"]

    static func scan(folder: URL) throws -> [PhotoItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let byBase = Dictionary(grouping: files) { $0.deletingPathExtension().lastPathComponent }

        var items: [PhotoItem] = []
        for (base, group) in byBase {
            let ext = { (url: URL) in url.pathExtension.lowercased() }
            let images = group.filter { imageExtensions.contains(ext($0)) }
            let raws = group.filter { rawExtensions.contains(ext($0)) }
            guard let primary = images.sorted(by: { rank($0) < rank($1) }).first ?? raws.first else { continue }
            let sidecars = group.filter { sidecarExtensions.contains(ext($0)) }
            let all = (images + raws + sidecars).sorted { $0.lastPathComponent < $1.lastPathComponent }
            let date = (try? primary.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            items.append(PhotoItem(baseName: base, files: all, primaryURL: primary, captureDate: date))
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
