import Foundation
import SwiftData

/// Ein Sortier-Durchgang (Ordner oder Apple-Fotos-Zeitraum).
@Model
final class SortRecord {
    var date: Date
    var sourceName: String
    /// "Ordner" oder "Apple Fotos"
    var sourceKind: String
    var analyzed: Int
    var kept: Int
    var rejected: Int
    /// Datenmenge der aussortierten Dateien (nur bei Ordnern bekannt).
    var rejectedBytes: Int64
    var protectedFavorites: Int

    init(date: Date = .now, sourceName: String, sourceKind: String, analyzed: Int, kept: Int, rejected: Int,
         rejectedBytes: Int64, protectedFavorites: Int) {
        self.date = date
        self.sourceName = sourceName
        self.sourceKind = sourceKind
        self.analyzed = analyzed
        self.kept = kept
        self.rejected = rejected
        self.rejectedBytes = rejectedBytes
        self.protectedFavorites = protectedFavorites
    }
}

/// Ein gespeichertes kombiniertes Gruppenfoto.
@Model
final class MergeRecord {
    var date: Date
    var sourceName: String
    var replacedFaces: Int

    init(date: Date = .now, sourceName: String, replacedFaces: Int) {
        self.date = date
        self.sourceName = sourceName
        self.replacedFaces = replacedFaces
    }
}

/// Lokale Statistik-Datenbank in ~/Library/Application Support/PhotoSorter.
@MainActor
enum StatsStore {
    static let container: ModelContainer = {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("PhotoSorter", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("Statistik.store"))
        do {
            return try ModelContainer(for: SortRecord.self, MergeRecord.self, configurations: configuration)
        } catch {
            // Notfalls nur im Speicher, damit die App trotzdem startet.
            return try! ModelContainer(for: SortRecord.self, MergeRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()

    @discardableResult
    static func record(_ record: SortRecord) -> SortRecord {
        container.mainContext.insert(record)
        try? container.mainContext.save()
        return record
    }

    static func recordMerge(sourceName: String, replacedFaces: Int) {
        container.mainContext.insert(MergeRecord(sourceName: sourceName, replacedFaces: replacedFaces))
        try? container.mainContext.save()
    }

    static func remove(_ record: SortRecord) {
        container.mainContext.delete(record)
        try? container.mainContext.save()
    }

    static func totalRejected() -> Int {
        let records = (try? container.mainContext.fetch(FetchDescriptor<SortRecord>())) ?? []
        return records.reduce(0) { $0 + $1.rejected }
    }
}
