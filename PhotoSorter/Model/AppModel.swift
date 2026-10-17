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
    var renameKept = true
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

    var filteredScenes: [PhotoScene] {
        scenes.filter { scene in
            switch filter {
            case .all: true
            case .withRejects: scene.photos.contains { decisions[$0.id]?.keep == false }
            case .series: scene.photos.count > 1
            case .groups: scene.category == .group
            case .portraits: scene.category == .portrait
            }
        }
    }

    // MARK: - Anwenden

    func apply() {
        guard let folder = folderURL else { return }
        let rejected = photos.filter { decisions[$0.id]?.keep == false }
        let kept = photos.filter { decisions[$0.id]?.keep != false }.map { ($0, $0.category) }
        do {
            lastResult = try FileOrganizer.apply(rejected: rejected, kept: kept, in: folder, renameKept: renameKept)
            phase = .applied
        } catch {
            errorMessage = "Aussortieren fehlgeschlagen (alle Änderungen wurden zurückgenommen): \(error.localizedDescription)"
        }
    }

    func undoApply() {
        guard let result = lastResult else { return }
        let errors = FileOrganizer.undo(result.moves, root: result.folder)
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
