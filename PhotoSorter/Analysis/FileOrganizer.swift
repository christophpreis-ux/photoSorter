import Foundation

struct FileMove: Hashable {
    let from: URL
    let to: URL
}

struct ApplyResult {
    let folder: URL
    let moves: [FileMove]
    let createdFolders: [URL]
    let rejectedPhotos: Int
    let sortedPhotos: Int
    let renamedPhotos: Int
    var rejectFolder: URL { folder.appendingPathComponent(FileOrganizer.rejectFolderName, isDirectory: true) }
}

/// Ein behaltenes Foto mit Zielordner (relativ zum Hauptordner, nil = bleibt liegen).
struct KeptPlacement {
    let item: PhotoItem
    let folder: String?
    let category: PhotoCategory
}

/// Verschiebt aussortierte Fotos in einen Unterordner (nichts wird gelöscht),
/// sortiert behaltene Fotos in Abschnitts-Ordner und benennt sie optional nach Kategorie um.
enum FileOrganizer {
    static let rejectFolderName = "Aussortiert"

    static func apply(rejected: [PhotoItem], kept: [KeptPlacement], extraFiles: [(url: URL, folder: String?)],
                      in root: URL, renameKept: Bool) throws -> ApplyResult {
        let fm = FileManager.default
        var moves: [FileMove] = []
        var created: [URL] = []
        var renamed = 0, sorted = 0

        func folder(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name, isDirectory: true)
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                created.append(url)
            }
            return url
        }
        func move(_ files: [URL], baseName: String, to directory: URL) throws {
            let targets = uniqueTargets(for: files, baseName: baseName, in: directory)
            for (source, target) in zip(files, targets) where source != target {
                try fm.moveItem(at: source, to: target)
                moves.append(FileMove(from: source, to: target))
            }
        }

        do {
            if !rejected.isEmpty {
                let directory = try folder(rejectFolderName)
                for item in rejected {
                    try move(item.files, baseName: item.baseName, to: directory)
                }
            }
            for placement in kept {
                let item = placement.item
                let prefix = placement.category.filePrefix + "_"
                let shouldRename = renameKept && !item.baseName.hasPrefix(prefix)
                guard placement.folder != nil || shouldRename else { continue }
                let directory = try placement.folder.map(folder) ?? item.primaryURL.deletingLastPathComponent()
                try move(item.files, baseName: shouldRename ? prefix + item.baseName : item.baseName, to: directory)
                if shouldRename { renamed += 1 }
                if placement.folder != nil { sorted += 1 }
            }
            for extra in extraFiles {
                guard let name = extra.folder, fm.fileExists(atPath: extra.url.path) else { continue }
                try move([extra.url], baseName: extra.url.deletingPathExtension().lastPathComponent, to: try folder(name))
            }
        } catch {
            undo(moves, createdFolders: created)
            throw error
        }
        return ApplyResult(folder: root, moves: moves, createdFolders: created, rejectedPhotos: rejected.count,
                           sortedPhotos: sorted, renamedPhotos: renamed)
    }

    /// Macht alle Verschiebungen rückgängig und entfernt angelegte, leere Ordner.
    @discardableResult
    static func undo(_ moves: [FileMove], createdFolders: [URL]) -> [Error] {
        let fm = FileManager.default
        var errors: [Error] = []
        for move in moves.reversed() {
            do { try fm.moveItem(at: move.to, to: move.from) } catch { errors.append(error) }
        }
        for folder in createdFolders.reversed() {
            if let contents = try? fm.contentsOfDirectory(atPath: folder.path), contents.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: folder)
            }
        }
        return errors
    }

    /// Findet freie Zieldateinamen – RAW/JPEG-Paare behalten denselben Basisnamen.
    private static func uniqueTargets(for files: [URL], baseName: String, in folder: URL) -> [URL] {
        var counter = 0
        while true {
            let base = counter == 0 ? baseName : "\(baseName)_\(counter)"
            let targets = files.map { folder.appendingPathComponent(base).appendingPathExtension($0.pathExtension) }
            if targets.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) || files.contains($0) }) { return targets }
            counter += 1
        }
    }
}
