import AppKit
import CoreGraphics

/// Kleine Vorschaubilder aus den bei der Analyse erzeugten JPEG-Daten.
enum ThumbnailStore {
    private static let cache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 4000
        return cache
    }()

    static func image(for photo: PhotoItem) -> NSImage? {
        let key = photo.id as NSUUID
        if let image = cache.object(forKey: key) { return image }
        guard let data = photo.analysis?.thumbnailData, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Größere Vorschauen für Inspektor und Vergleichsansicht – werden bei Bedarf aus der Originaldatei geladen.
enum PreviewLoader {
    private static let cache: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.countLimit = 60
        return cache
    }()

    static func load(_ url: URL, maxPixel: Int = 2000) async -> CGImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        let image = await Task.detached(priority: .userInitiated) {
            ImageAnalyzer.loadImage(url: url, maxPixel: maxPixel)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}
