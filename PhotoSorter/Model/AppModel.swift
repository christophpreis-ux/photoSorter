import Foundation
import AppKit
import Observation

/// Woher die Fotos kommen.
enum PhotoSource: Equatable {
    case folder(URL)
    case photos(year: Int, month: Int?)

    var title: String {
        switch self {
        case .folder(let url): url.lastPathComponent
        case .photos(let year, let month):
            if let month { "Apple Fotos · " + Calendar.current.standaloneMonthSymbols[month - 1] + " \(year)" }
            else { "Apple Fotos · \(year)" }
        }
    }

    var kindName: String {
        switch self {
        case .folder: "Ordner"
        case .photos: "Apple Fotos"
        }
    }
}

/// Eintrag in der Seitenleiste.
enum SidebarItem: Hashable {
    case chapter(UUID)
    case merge
    case stats
}

/// Zustand eines Kombinier-Vorschlags.
enum MergeState {
    case working
    case ready(MergeResult)
    case failed
    case saving
    case saved
}

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

    private(set) var source: PhotoSource?
    var folderURL: URL? {
        if case .folder(let url) = source { return url }
        return nil
    }
    var isPhotosSource: Bool {
        if case .photos = source { return true }
        return false
    }

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
    var sidebarSelection: SidebarItem?
    var filter: SceneFilter = .all
    var thumbnailSize: Double = 130
    var lastResult: ApplyResult?
    /// Anzahl der in Apple Fotos gelöschten Fotos beim letzten Durchgang.
    var lastPhotosDeleted: Int?
    var errorMessage: String?
    var showPhotosPicker = false
    var showStats = false

    // Kombinieren
    private(set) var mergeStates: [UUID: MergeState] = [:]
    private var approvedMerges: Set<UUID> = []
    private(set) var dismissedMerges: Set<UUID> = []
    private var mergeTask: Task<Void, Never>?

    private var analysisTask: Task<Void, Never>?
    private var lastRecord: SortRecord?

    // MARK: - Quelle wählen

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
        start(source: .folder(folder)) { try PhotoScanner.scan(folder: folder) }
    }

    func openPhotos(year: Int, month: Int?) {
        start(source: .photos(year: year, month: month)) { PhotosLibrary.items(year: year, month: month) }
    }

    private func start(source: PhotoSource, items: @escaping @Sendable () throws -> [PhotoItem]) {
        analysisTask?.cancel()
        mergeTask?.cancel()
        self.source = source
        photos = []
        scenes = []
        evaluations = [:]
        decisions = [:]
        overrides = [:]
        chapters = []
        mergedFiles = [:]
        mergeStates = [:]
        approvedMerges = []
        dismissedMerges = []
        selectedPhotoID = nil
        sidebarSelection = nil
        lastResult = nil
        lastPhotosDeleted = nil
        lastRecord = nil
        errorMessage = nil
        phase = .scanning
        analysisTask = Task { await analyze(makeItems: items) }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        phase = .idle
    }

    private func analyze(makeItems: @escaping @Sendable () throws -> [PhotoItem]) async {
        let items: [PhotoItem]
        do {
            items = try await Task.detached(priority: .userInitiated) { try makeItems() }.value
        } catch {
            errorMessage = "Fotos konnten nicht gelesen werden: \(error.localizedDescription)"
            phase = .idle
            return
        }
        guard !items.isEmpty else {
            errorMessage = isPhotosSource ? "In diesem Zeitraum gibt es keine Fotos." : "In diesem Ordner wurden keine Fotos gefunden."
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
        // Zum Testen: `-openSidebar merge|stats`
        switch UserDefaults.standard.string(forKey: "openSidebar") {
        case "merge": sidebarSelection = .merge
        case "stats": sidebarSelection = .stats
        default: break
        }
    }

    // MARK: - Szenen & Entscheidungen

    func regroup() {
        let groups = SceneGrouper.group(photos, settings: grouping)
        scenes = groups.enumerated().map { PhotoScene(index: $0.offset + 1, photos: $0.element) }
        evaluations = Dictionary(uniqueKeysWithValues: scenes.map { ($0.id, SelectionEngine.evaluate(scene: $0)) })
        sceneOfPhoto = [:]
        for scene in scenes { for photo in scene.photos { sceneOfPhoto[photo.id] = scene.id } }
        mergeStates = [:]
        updateDecisions()
        detectChapters()
    }

    private func updateDecisions() {
        // Favoriten aus Apple Fotos werden immer behalten – sie gehen als feste Entscheidung in die Auswahl ein.
        var effective = overrides
        for photo in photos where photo.isFavorite { effective[photo.id] = true }

        var all: [UUID: Decision] = [:]
        for scene in scenes {
            guard let evaluation = evaluations[scene.id] else { continue }
            all.merge(SelectionEngine.decide(evaluation, strictness: strictness, overrides: effective)) { $1 }
        }
        for photo in photos where photo.isFavorite {
            all[photo.id]?.keep = true
            all[photo.id]?.isFavorite = true
            all[photo.id]?.isManual = false
            all[photo.id]?.reason = "Favorit in Apple Fotos – wird immer behalten"
        }
        decisions = all
    }

    func decision(for photo: PhotoItem) -> Decision? { decisions[photo.id] }

    func setOverride(_ keep: Bool?, for photo: PhotoItem) {
        guard !photo.isFavorite else { return }
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
    var favoriteCount: Int { photos.filter(\.isFavorite).count }

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

    /// Alle Szenen, in denen ein Gruppenfoto kombiniert werden kann.
    var mergeQueue: [(scene: PhotoScene, candidate: MergeCandidate)] {
        scenes.compactMap { scene in
            guard !dismissedMerges.contains(scene.id), let candidate = mergeCandidate(for: scene) else { return nil }
            return (scene, candidate)
        }
    }

    var openMergeCount: Int {
        mergeQueue.filter { item in
            switch mergeStates[item.scene.id] {
            case .saved, .failed: false
            default: true
            }
        }.count
    }

    /// Erstellt die Vorschauen aller Vorschläge nacheinander im Hintergrund.
    func prepareMerges() {
        guard mergeTask == nil else { return }
        mergeTask = Task {
            while let next = mergeQueue.first(where: { mergeStates[$0.scene.id] == nil }) {
                if Task.isCancelled { break }
                await generateMerge(scene: next.scene, candidate: next.candidate)
            }
            mergeTask = nil
        }
    }

    private func generateMerge(scene: PhotoScene, candidate: MergeCandidate) async {
        guard let tracks = evaluations[scene.id]?.tracks else { return }
        mergeStates[scene.id] = .working
        let result = await Task.detached(priority: .userInitiated) { FaceMerger.merge(candidate, tracks: tracks) }.value
        guard let result, !result.faceCrops.isEmpty else {
            mergeStates[scene.id] = .failed
            return
        }
        mergeStates[scene.id] = .ready(result)
        if approvedMerges.contains(scene.id) { await save(result, scene: scene) }
    }

    /// Ein Klick: übernehmen (und bei Bedarf erst erzeugen).
    func approveMerge(_ scene: PhotoScene) {
        switch mergeStates[scene.id] {
        case .ready(let result):
            Task { await save(result, scene: scene) }
        case .saved, .saving, .failed:
            break
        default:
            approvedMerges.insert(scene.id)
            prepareMerges()
        }
    }

    func approveAllMerges() {
        for item in mergeQueue { approveMerge(item.scene) }
    }

    func dismissMerge(_ scene: PhotoScene) {
        dismissedMerges.insert(scene.id)
    }

    private func save(_ result: MergeResult, scene: PhotoScene) async {
        mergeStates[scene.id] = .saving
        do {
            _ = try await saveMerge(result, scene: scene)
            mergeStates[scene.id] = .saved
        } catch {
            mergeStates[scene.id] = .ready(result)
            errorMessage = "Speichern fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    /// Speichert ein kombiniertes Foto – neben dem Original bzw. als neues Foto in Apple Fotos.
    func saveMerge(_ result: MergeResult, scene: PhotoScene) async throws -> URL {
        let url: URL
        if isPhotosSource {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoSorter", isDirectory: true)
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            let file = try await Task.detached(priority: .userInitiated) { try FaceMerger.save(result, to: temp) }.value
            try await PhotosLibrary.importImage(at: file, creationDate: result.base.captureDate)
            try? FileManager.default.removeItem(at: file)
            url = file
        } else {
            url = try await Task.detached(priority: .userInitiated) { try FaceMerger.save(result) }.value
            mergedFiles[scene.id, default: []].append(url)
        }
        mergeStates[scene.id] = .saved
        StatsStore.recordMerge(sourceName: source?.title ?? "", replacedFaces: result.faceCrops.count)
        return url
    }

    // MARK: - Anwenden

    func apply() {
        if isPhotosSource {
            Task { await applyToPhotos() }
            return
        }
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
        let bytes = rejected.flatMap(\.files).reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        do {
            lastResult = try FileOrganizer.apply(rejected: rejected, kept: kept, extraFiles: extras, in: folder,
                                                 renameKept: renameKept)
            lastRecord = StatsStore.record(SortRecord(sourceName: source?.title ?? "", sourceKind: "Ordner",
                                                      analyzed: photos.count, kept: kept.count, rejected: rejected.count,
                                                      rejectedBytes: bytes, protectedFavorites: 0))
            phase = .applied
        } catch {
            errorMessage = "Aussortieren fehlgeschlagen (alle Änderungen wurden zurückgenommen): \(error.localizedDescription)"
        }
    }

    /// Apple Fotos: Aussortiertes in „Zuletzt gelöscht“ verschieben. Favoriten werden niemals gelöscht.
    private func applyToPhotos() async {
        let rejected = photos.filter { decisions[$0.id]?.keep == false && !$0.isFavorite }
        let assets = rejected.compactMap { PhotosLibrary.asset(for: $0.primaryURL) }.filter { !$0.isFavorite }
        guard !assets.isEmpty else {
            errorMessage = "Es gibt nichts zu löschen."
            return
        }
        do {
            try await PhotosLibrary.moveToTrash(assets)
            lastPhotosDeleted = assets.count
            lastRecord = StatsStore.record(SortRecord(sourceName: source?.title ?? "", sourceKind: "Apple Fotos",
                                                      analyzed: photos.count, kept: photos.count - assets.count,
                                                      rejected: assets.count, rejectedBytes: 0,
                                                      protectedFavorites: favoriteCount))
            phase = .applied
        } catch {
            errorMessage = "Löschen wurde abgebrochen oder ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func undoApply() {
        guard let result = lastResult else { return }
        let errors = FileOrganizer.undo(result.moves, createdFolders: result.createdFolders)
        if !errors.isEmpty {
            errorMessage = "\(errors.count) Dateien konnten nicht zurückverschoben werden."
        }
        if let lastRecord { StatsStore.remove(lastRecord) }
        lastRecord = nil
        lastResult = nil
        phase = .review
    }

    func reopenSource() {
        switch source {
        case .folder(let url): open(folder: url)
        case .photos(let year, let month): openPhotos(year: year, month: month)
        case nil: break
        }
    }

    func revealInFinder(_ url: URL) {
        guard !PhotosLibrary.isPhotosURL(url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    var rejectedFileCount: Int {
        photos.filter { decisions[$0.id]?.keep == false }.reduce(0) { $0 + $1.files.count }
    }
}
