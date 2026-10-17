import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class AppModel {
    enum Phase: Equatable {
        case idle, scanning, analyzing, review, applied
    }

    var phase: Phase = .idle
    var progressDone = 0
    var progressTotal = 0
    var analysisStart = Date()

    var folderURL: URL?
    private(set) var photos: [PhotoItem] = []
    private(set) var scenes: [PhotoScene] = []
    private(set) var evaluations: [UUID: SceneEvaluation] = [:]
    private(set) var decisions: [UUID: Decision] = [:]
    private var overrides: [UUID: Bool] = [:]
    private var sceneOfPhoto: [UUID: UUID] = [:]
    /// Abschnitte des Shootings (Trauung, Sektempfang, Gruppenfotos …).
    var chapters: [EventChapter] = []
    /// Gespeicherte kombinierte Gruppenfotos je Szene – wandern beim Sortieren mit in den Abschnitts-Ordner.
    private(set) var mergedFiles: [UUID: [URL]] = [:]

    /// 0 = nichts aussortieren, 1 = nur das beste Foto pro Szene.
    var strictness: Double = 0.5 {
        didSet { updateDecisions() }
    }
    var grouping = GroupingSettings() {
        didSet { if grouping != oldValue, phase == .review { regroup() } }
    }

    var selectedPhotoID: UUID?
    var showInspector = false
    var compareScene: PhotoScene?
    var renameKept = false
    /// Behaltene Fotos in Ordner pro Abschnitt sortieren (z. B. "03 Sektempfang").
    var sortIntoChapterFolders = true
    var selectedChapterID: UUID?
    var filter: SceneFilter = .all
    var thumbnailSize: Double = 130
    var lastResult: ApplyResult?
    var errorMessage: String?

    private var analysisTask: Task<Void, Never>?

    // MARK: - Ordner laden

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Analysieren"
        panel.message = "Wähle einen Ordner mit Fotos (JPEG, HEIC, RAW …)"
        if panel.runModal() == .OK, let url = panel.url {
            open(folder: url)
        }
    }

    func open(folder: URL) {
        analysisTask?.cancel()
        folderURL = folder
        photos = []
        scenes = []
        evaluations = [:]
        decisions = [:]
        overrides = [:]
        chapters = []
        mergedFiles = [:]
        selectedPhotoID = nil
        lastResult = nil
        errorMessage = nil
        phase = .scanning
        analysisTask = Task { await analyze(folder: folder) }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        phase = .idle
    }

    private func analyze(folder: URL) async {
        let items: [PhotoItem]
        do {
            items = try await Task.detached(priority: .userInitiated) { try PhotoScanner.scan(folder: folder) }.value
        } catch {
            errorMessage = "Ordner konnte nicht gelesen werden: \(error.localizedDescription)"
            phase = .idle
            return
        }
        guard !items.isEmpty else {
            errorMessage = "In diesem Ordner wurden keine Fotos gefunden."
            phase = .idle
            return
        }

        progressTotal = items.count
        progressDone = 0
        analysisStart = Date()
        phase = .analyzing

        let inputs = items.map { ($0.primaryURL, $0.isRawPrimary) }
        let parallel = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))

        await withTaskGroup(of: (Int, AnalysisOutput?).self) { group in
            var next = 0
            while next < min(parallel, inputs.count) {
                let index = next, (url, isRaw) = inputs[index]
                group.addTask(priority: .userInitiated) { (index, ImageAnalyzer.analyze(url: url, isRaw: isRaw)) }
                next += 1
            }
            for await (index, output) in group {
                if let output {
                    items[index].analysis = output.analysis
                    items[index].captureDate = output.captureDate
                }
                progressDone += 1
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if next < inputs.count {
                    let index = next, (url, isRaw) = inputs[index]
                    group.addTask(priority: .userInitiated) { (index, ImageAnalyzer.analyze(url: url, isRaw: isRaw)) }
                    next += 1
                }
            }
        }
        guard !Task.isCancelled else { return }

        photos = items
        regroup()
        phase = .review
    }

    // MARK: - Szenen & Entscheidungen

    func regroup() {
        let groups = SceneGrouper.group(photos, settings: grouping)
        scenes = groups.enumerated().map { PhotoScene(index: $0.offset + 1, photos: $0.element) }
        evaluations = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, SelectionEngine.evaluate(scene: $0)) })
        sceneOfPhoto = [:]
        for scene in scenes { for photo in scene.photos { sceneOfPhoto[photo.id] = scene.id } }
        updateDecisions()
        detectChapters()
    }

    // MARK: - Abschnitte

    func detectChapters() {
        chapters = EventDetector.detect(scenes: scenes, settings: grouping)
        // Unbekannte Abschnitte vom On-Device-Sprachmodell benennen lassen (falls verfügbar).
        for chapter in chapters where chapter.kind == .other {
            let photos = self.scenes(in: chapter).flatMap(\.photos)
            let faces = Double(photos.reduce(0) { $0 + ($1.analysis?.faces.count ?? 0) }) / Double(max(photos.count, 1))
            let labels = chapter.topLabels, count = photos.count, id = chapter.id
            Task {
                guard let name = await ChapterNamer.suggestName(labels: labels, photoCount: count, averageFaces: faces),
                      let index = chapters.firstIndex(where: { $0.id == id }), !chapters[index].isNameCustom else { return }
                chapters[index].name = name
            }
        }
    }

    func scenes(in chapter: EventChapter) -> [PhotoScene] {
        let ids = Set(chapter.sceneIDs)
        return scenes.filter { ids.contains($0.id) }
    }

    func chapter(of scene: PhotoScene) -> EventChapter? {
        chapters.first { $0.sceneIDs.contains(scene.id) }
    }

    func folderName(for chapter: EventChapter) -> String {
        let index = (chapters.firstIndex { $0.id == chapter.id } ?? 0) + 1
        return EventDetector.folderName(index: index, name: chapter.name)
    }

    func renameChapter(_ id: UUID, to name: String) {
        guard let index = chapters.firstIndex(where: { $0.id == id }) else { return }
        chapters[index].name = name
        chapters[index].isNameCustom = true
    }

    func setKind(_ kind: EventKind, for id: UUID) {
        guard let index = chapters.firstIndex(where: { $0.id == id }) else { return }
        chapters[index].kind = kind
        if !chapters[index].isNameCustom {
            chapters[index].name = EventDetector.defaultName(kind: kind, start: scenes(in: chapters[index]).first?.startDate ?? .now)
        }
    }

    func mergeWithPrevious(_ id: UUID) {
        guard let index = chapters.firstIndex(where: { $0.id == id }), index > 0 else { return }
        chapters[index - 1].sceneIDs += chapters[index].sceneIDs
        chapters.remove(at: index)
    }

    /// Beginnt ab dieser Szene einen neuen Abschnitt.
    func splitChapter(at scene: PhotoScene) {
        guard let index = chapters.firstIndex(where: { $0.sceneIDs.contains(scene.id) }),
              let position = chapters[index].sceneIDs.firstIndex(of: scene.id), position > 0 else { return }
        let tail = Array(chapters[index].sceneIDs[position...])
        chapters[index].sceneIDs.removeSubrange(position...)
        let photos = scenes.filter { tail.contains($0.id) }.flatMap(\.photos)
        let kind = EventDetector.kind(for: photos)
        let chapter = EventChapter(sceneIDs: tail, kind: kind, name: EventDetector.defaultName(kind: kind, start: scene.startDate),
                                   topLabels: EventDetector.topLabels(photos))
        chapters.insert(chapter, at: index + 1)
    }

    func photoCount(of chapter: EventChapter) -> (total: Int, kept: Int) {
        let photos = scenes(in: chapter).flatMap(\.photos)
        return (photos.count, photos.filter { decisions[$0.id]?.keep != false }.count)
    }

    // MARK: - Gruppenfotos kombinieren

    func mergeCandidate(for scene: PhotoScene) -> MergeCandidate? {
        guard let evaluation = evaluations[scene.id] else { return nil }
        return FaceMerger.candidate(scene: scene, evaluation: evaluation, decisions: decisions)
    }

    func saveMerge(_ result: MergeResult, scene: PhotoScene) throws -> URL {
        let url = try FaceMerger.save(result)
        mergedFiles[scene.id, default: []].append(url)
        return url
    }

    private func updateDecisions() {
        var all: [UUID: Decision] = [:]
        for scene in scenes {
            guard let evaluation = evaluations[scene.id] else { continue }
            all.merge(SelectionEngine.decide(evaluation, strictness: strictness, overrides: overrides)) { $1 }
        }
        decisions = all
    }

    func decision(for photo: PhotoItem) -> Decision? { decisions[photo.id] }

    func setOverride(_ keep: Bool?, for photo: PhotoItem) {
        overrides[photo.id] = keep
        updateDecisions()
    }

    func toggle(_ photo: PhotoItem) {
        let keep = decisions[photo.id]?.keep ?? true
        setOverride(!keep, for: photo)
    }

    func resetOverrides() {
        overrides = [:]
        updateDecisions()
    }

    var hasOverrides: Bool { !overrides.isEmpty }

    func scene(of photo: PhotoItem) -> PhotoScene? {
        guard let id = sceneOfPhoto[photo.id] else { return nil }
        return scenes.first { $0.id == id }
    }

    var selectedPhoto: PhotoItem? {
        guard let id = selectedPhotoID else { return nil }
        return photos.first { $0.id == id }
    }

    var keptCount: Int { decisions.values.filter(\.keep).count }
    var rejectedCount: Int { decisions.values.filter { !$0.keep }.count }

    func filteredScenes(in chapter: EventChapter) -> [PhotoScene] {
        scenes(in: chapter).filter(passesFilter)
    }

    private func passesFilter(_ scene: PhotoScene) -> Bool {
        switch filter {
        case .all: true
        case .mergeable: mergeCandidate(for: scene) != nil
        case .withRejects: scene.photos.contains { decisions[$0.id]?.keep == false }
        case .series: scene.photos.count > 1
        case .groups: scene.category == .group
        case .portraits: scene.category == .portrait
        }
    }

    // MARK: - Anwenden

    func apply() {
        guard let folder = folderURL else { return }
        let rejected = photos.filter { decisions[$0.id]?.keep == false }
        var folderOfScene: [UUID: String] = [:]
        if sortIntoChapterFolders {
            for chapter in chapters {
                let name = folderName(for: chapter)
                for id in chapter.sceneIDs { folderOfScene[id] = name }
            }
        }
        let kept = photos.filter { decisions[$0.id]?.keep != false }.map { photo in
            KeptPlacement(item: photo, folder: sceneOfPhoto[photo.id].flatMap { folderOfScene[$0] }, category: photo.category)
        }
        let extras = mergedFiles.flatMap { sceneID, urls in urls.map { (url: $0, folder: folderOfScene[sceneID]) } }
        do {
            lastResult = try FileOrganizer.apply(rejected: rejected, kept: kept, extraFiles: extras, in: folder,
                                                 renameKept: renameKept)
            phase = .applied
        } catch {
            errorMessage = "Aussortieren fehlgeschlagen (alle Änderungen wurden zurückgenommen): \(error.localizedDescription)"
        }
    }

    func undoApply() {
        guard let result = lastResult else { return }
        let errors = FileOrganizer.undo(result.moves, createdFolders: result.createdFolders)
        if !errors.isEmpty {
            errorMessage = "\(errors.count) Dateien konnten nicht zurückverschoben werden."
        }
        lastResult = nil
        phase = .review
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var rejectedFileCount: Int {
        photos.filter { decisions[$0.id]?.keep == false }.reduce(0) { $0 + $1.files.count }
    }
}
