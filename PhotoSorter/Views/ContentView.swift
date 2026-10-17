import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .idle:
                WelcomeView()
            case .scanning, .analyzing:
                AnalysisProgressView()
            case .review:
                ReviewView()
            case .applied:
                AppliedView()
            }
        }
        .navigationTitle(model.folderURL?.lastPathComponent ?? "PhotoSorter")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Ordner wählen", systemImage: "folder.badge.plus")
                }
                .help("Ordner mit Fotos auswählen (⌘O)")
            }
        }
        .task {
            // Zum Testen: `PhotoSorter -openFolder /pfad/zum/ordner`
            if model.phase == .idle, let path = UserDefaults.standard.string(forKey: "openFolder") {
                model.open(folder: URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.hasDirectoryPath else { return false }
            model.open(folder: url)
            return true
        }
        .alert("Hinweis", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $model.compareScene) { scene in
            SceneCompareView(scene: scene)
                .environment(model)
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .review: "\(model.photos.count) Fotos · \(model.scenes.count) Szenen"
        case .analyzing: "Analysiere …"
        default: ""
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            VStack(spacing: 8) {
                Text("PhotoSorter")
                    .font(.largeTitle.bold())
                Text("Findet ähnliche Fotos, erkennt geschlossene Augen und Unschärfe\nund schlägt vor, was du behalten solltest – komplett auf deinem Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button {
                model.chooseFolder()
            } label: {
                Label("Ordner auswählen", systemImage: "folder")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .controlSize(.extraLarge)
            .buttonStyle(.glassProminent)
            Text("oder Ordner hierher ziehen · JPEG, HEIC, PNG, TIFF und RAW (CR3, NEF, ARW, DNG, RAF …)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(48)
        .glassPanel(cornerRadius: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct AnalysisProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            if model.phase == .scanning {
                ProgressView("Suche Fotos …")
            } else {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)
                Text("Analysiere Fotos")
                    .font(.title2.bold())
                ProgressView(value: Double(model.progressDone), total: Double(max(model.progressTotal, 1)))
                    .frame(width: 380)
                Text("\(model.progressDone) von \(model.progressTotal)\(eta)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("Schärfe · Augen · Gesichtsqualität · Belichtung · Ähnlichkeit")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button("Abbrechen", role: .cancel) { model.cancelAnalysis() }
                .buttonStyle(.glass)
        }
        .padding(40)
        .glassPanel(cornerRadius: 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private var eta: String {
        guard model.progressDone > 10 else { return "" }
        let elapsed = Date().timeIntervalSince(model.analysisStart)
        let remaining = elapsed / Double(model.progressDone) * Double(model.progressTotal - model.progressDone)
        guard remaining > 3 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = remaining > 60 ? [.minute] : [.second]
        return " · noch ca. " + (formatter.string(from: remaining) ?? "")
    }
}

struct AppliedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.keep)
            Text("Fertig sortiert")
                .font(.largeTitle.bold())
            if let result = model.lastResult {
                VStack(spacing: 6) {
                    Text("\(result.rejectedPhotos) Fotos wurden in den Ordner „\(FileOrganizer.rejectFolderName)“ verschoben.")
                    if result.sortedPhotos > 0 {
                        Text("\(result.sortedPhotos) behaltene Fotos wurden in \(model.chapters.count) Abschnitts-Ordner sortiert.")
                    }
                    if result.renamedPhotos > 0 {
                        Text("\(result.renamedPhotos) behaltene Fotos wurden nach Kategorie umbenannt.")
                    }
                    Text("Es wurde nichts gelöscht.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        model.revealInFinder(result.sortedPhotos > 0 || result.rejectedPhotos == 0 ? result.folder : result.rejectFolder)
                    } label: {
                        Label("Im Finder zeigen", systemImage: "folder")
                    }
                    Button {
                        withAnimation { model.undoApply() }
                    } label: {
                        Label("Rückgängig", systemImage: "arrow.uturn.backward")
                    }
                    Button {
                        if let folder = model.folderURL { model.open(folder: folder) }
                    } label: {
                        Label("Ordner neu analysieren", systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.large)
                .buttonStyle(.glass)
            }
        }
        .padding(44)
        .glassPanel(cornerRadius: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
