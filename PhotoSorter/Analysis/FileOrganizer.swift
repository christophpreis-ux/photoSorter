import Foundation

struct FileMove: Hashable {
    let from: URL
    let to: URL
}

struct ApplyResult {
    let folder: URL
    let moves: [FileMove]
    let rejectedPhotos: Int
    let renamedPhotos: Int
    var rejectFolder: URL { folder.appendingPathComponent(FileOrganizer.rejectFolderName, isDirectory: true) }
}

/// Verschiebt aussortierte Fotos in einen Unterordner (nichts wird gelöscht)
/// und benennt behaltene Fotos optional nach Kategorie um.
enum FileOrganizer {
    static let rejectFolderName = "Aussortiert"

    static func apply(rejected: [PhotoItem], kept: [(PhotoItem, PhotoCategory)], in root: URL, renameKept: Bool) throws -> ApplyResult {
        let fm = FileManager.default
        var moves: [FileMove] = []
        var renamed = 0
        do {
            if !rejected.isEmpty {
                let folder = root.appendingPathComponent(rejectFolderName, isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                for item in rejected {
                    let targets = uniqueTargets(for: item.files, baseName: item.baseName, in: folder)
                    for (source, target) in zip(item.files, targets) {
                        try fm.moveItem(at: source, to: target)
                        moves.append(FileMove(from: source, to: target))
                    }
                }
            }
            if renameKept {
                for (item, category) in kept {
                    let prefix = category.filePrefix + "_"
                    guard !item.baseName.hasPrefix(prefix) else { continue }
                    let targets = uniqueTargets(for: item.files, baseName: prefix + item.baseName, in: root)
                    for (source, target) in zip(item.files, targets) {
                        try fm.moveItem(at: source, to: target)
                        moves.append(FileMove(from: source, to: target))
                    }
                    renamed += 1
                }
            }
        } catch {
            undo(moves, root: root)
            throw error
        }
        return ApplyResult(folder: root, moves: moves, rejectedPhotos: rejected.count, renamedPhotos: renamed)
    }

    /// Macht alle Verschiebungen rückgängig.
    @discardableResult
    static func undo(_ moves: [FileMove], root: URL) -> [Error] {
        let fm = FileManager.default
        var errors: [Error] = []
        for move in moves.reversed() {
            do { try fm.moveItem(at: move.to, to: move.from) } catch { errors.append(error) }
        }
        let folder = root.appendingPathComponent(rejectFolderName, isDirectory: true)
        if let contents = try? fm.contentsOfDirectory(atPath: folder.path),
           contents.allSatisfy({ $0 == ".DS_Store" }) {
            try? fm.removeItem(at: folder)
        }
        return errors
    }

    /// Findet freie Zieldateinamen – RAW/JPEG-Paare behalten denselben Basisnamen.
    private static func uniqueTargets(for files: [URL], baseName: String, in folder: URL) -> [URL] {
        var counter = 0
        while true {
            let base = counter == 0 ? baseName : "\(baseName)_\(counter)"
            let targets = files.map { folder.appendingPathComponent(base).appendingPathExtension($0.pathExtension) }
            if targets.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) { return targets }
            counter += 1
        }
    }
}
