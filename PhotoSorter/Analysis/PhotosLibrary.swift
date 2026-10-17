import Foundation
import Photos
import AppKit
import CoreImage

/// Zugriff auf die Apple-Fotos-Mediathek (PhotoKit).
/// Fotos aus der Mediathek werden intern über URLs der Form `photos://asset/<localIdentifier>` angesprochen,
/// damit der Rest der App (Analyse, Vorschau, Kombinieren) wie mit Dateien arbeiten kann.
enum PhotosLibrary {
    static let scheme = "photos"
    private static let prefix = "photos://asset/"
    /// iCloud-Fotos bei Bedarf herunterladen (langsamer, aber vollständig).
    nonisolated(unsafe) static var allowNetworkAccess = true

    private static let lock = NSLock()
    nonisolated(unsafe) private static var assetCache: [String: PHAsset] = [:]

    // MARK: - Berechtigung

    static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Abfragen

    static func dateRange(year: Int, month: Int?) -> (Date, Date) {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: month ?? 1, day: 1))!
        let end = calendar.date(byAdding: month == nil ? .year : .month, value: 1, to: start)!
        return (start, end)
    }

    static func fetchResult(year: Int, month: Int?) -> PHFetchResult<PHAsset> {
        let (start, end) = dateRange(year: year, month: month)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    static func count(year: Int, month: Int?) -> Int { fetchResult(year: year, month: month).count }

    /// Jahre, aus denen Fotos in der Mediathek vorhanden sind (neuestes zuerst).
    static func availableYears() -> [Int] {
        func edge(ascending: Bool) -> Date? {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: ascending)]
            options.fetchLimit = 1
            return PHAsset.fetchAssets(with: .image, options: options).firstObject?.creationDate
        }
        let calendar = Calendar.current
        guard let oldest = edge(ascending: true), let newest = edge(ascending: false) else { return [] }
        return Array((calendar.component(.year, from: oldest)...calendar.component(.year, from: newest)).reversed())
    }

    /// Erzeugt PhotoItems für alle Fotos im Zeitraum.
    static func items(year: Int, month: Int?) -> [PhotoItem] {
        var items: [PhotoItem] = []
        let result = fetchResult(year: year, month: month)
        result.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let name = resources.first?.originalFilename ?? asset.localIdentifier
            let item = PhotoItem(baseName: (name as NSString).deletingPathExtension, files: [],
                                 primaryURL: url(for: asset), captureDate: asset.creationDate ?? .distantPast)
            item.isFavorite = asset.isFavorite
            item.byteSize = resources.reduce(Int64(0)) { $0 + fileSize(of: $1) }
            items.append(item)
            lock.withLock { assetCache[asset.localIdentifier] = asset }
        }
        return items
    }

    /// Dateigröße einer Ressource. PhotoKit bietet dafür keine offizielle API – daher vorsichtig per Key-Value-Coding,
    /// nur wenn die Eigenschaft existiert (sonst 0, statt abzustürzen).
    private static func fileSize(of resource: PHAssetResource) -> Int64 {
        guard resource.responds(to: NSSelectorFromString("fileSize")) else { return 0 }
        return (resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - URLs

    static func url(for asset: PHAsset) -> URL {
        let encoded = asset.localIdentifier.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? asset.localIdentifier
        return URL(string: prefix + encoded)!
    }

    static func isPhotosURL(_ url: URL) -> Bool { url.scheme == scheme }

    static func asset(for url: URL) -> PHAsset? {
        guard isPhotosURL(url), let id = url.absoluteString.dropFirst(prefix.count).removingPercentEncoding else { return nil }
        if let cached = lock.withLock({ assetCache[id] }) { return cached }
        let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        if let asset { lock.withLock { assetCache[id] = asset } }
        return asset
    }

    // MARK: - Bilder laden (synchron, im Hintergrund aufrufen)

    static func image(for asset: PHAsset, maxPixel: Int) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetworkAccess
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: maxPixel, height: maxPixel),
                                              contentMode: .aspectFit, options: options) { image, _ in
            result = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return result
    }

    static func image(for url: URL, maxPixel: Int) -> CGImage? {
        asset(for: url).flatMap { image(for: $0, maxPixel: maxPixel) }
    }

    /// Originalbild in voller Auflösung (für das Kombinieren von Gruppenfotos).
    static func fullImage(for url: URL) -> CIImage? {
        guard let asset = asset(for: url) else { return nil }
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        var data: Data?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { imageData, _, _, _ in
            data = imageData
        }
        guard let data else { return nil }
        return CIImage(data: data, options: [.applyOrientationProperty: true])
    }

    // MARK: - Ändern

    /// Verschiebt Fotos in „Zuletzt gelöscht“ (30 Tage wiederherstellbar). macOS fragt dabei selbst nach.
    static func moveToTrash(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    /// Legt ein neues Foto (z. B. kombiniertes Gruppenfoto) in der Mediathek an.
    static func importImage(at url: URL, creationDate: Date?) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            request?.creationDate = creationDate
        }
    }
}
