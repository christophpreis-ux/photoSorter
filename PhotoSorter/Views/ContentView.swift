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
        .overlay {
            if model.phase == .review, let photo = model.previewPhoto {
                PhotoPreviewOverlay(photo: photo)
                    .transition(.opacity)
            }
        }
        .navigationTitle(model.source?.title ?? "PhotoSorter")
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
            ToolbarItem(placement: .principal) {
                if model.phase != .idle { StepIndicator() }
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    model.showPhotosPicker = true
                } label: {
                    Label("Apple Fotos", systemImage: "photo.on.rectangle.angled")
                }
                .help("Jahr oder Monat aus Apple Fotos analysieren")
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
        .sheet(isPresented: $model.showLightroom) {
            LightroomExportView()
                .environment(model)
        }
        .sheet(isPresented: $model.showPhotosPicker) {
            PhotosSourcePicker()
                .environment(model)
        }
        .sheet(isPresented: $model.showStats) {
            VStack(spacing: 0) {
                StatsView()
                HStack {
                    Spacer()
                    Button("Fertig") { model.showStats = false }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .frame(minWidth: 760, minHeight: 640)
            .background(Theme.background)
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
    @State private var totalRejected = 0

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
            HStack(spacing: 12) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Ordner auswählen", systemImage: "folder")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                Button {
                    model.showPhotosPicker = true
                } label: {
                    Label("Apple Fotos", systemImage: "photo.on.rectangle.angled")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.extraLarge)
            Text("oder Ordner hierher ziehen · JPEG, HEIC, PNG, TIFF und RAW (CR3, NEF, ARW, DNG, RAF …)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                model.showStats = true
            } label: {
                Label(totalRejected > 0 ? "Bisher \(totalRejected.formatted()) Fotos aussortiert" : "Statistik",
                      systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.glass)
        }
        .padding(48)
        .glassPanel(cornerRadius: 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { totalRejected = StatsStore.totalRejected() }
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
            if let deleted = model.lastPhotosDeleted {
                VStack(spacing: 6) {
                    Text("\(deleted) Fotos wurden in Apple Fotos nach „Zuletzt gelöscht“ verschoben.")
                    Text("\(model.favoriteCount) Favoriten wurden behalten. Gelöschte Fotos sind 30 Tage wiederherstellbar.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        if let url = URL(string: "photos://") { NSWorkspace.shared.open(url) }
                    } label: {
                        Label("Fotos öffnen", systemImage: "photo.on.rectangle.angled")
                    }
                    Button {
                        model.reopenSource()
                    } label: {
                        Label("Zeitraum neu analysieren", systemImage: "arrow.clockwise")
                    }
                    Button {
                        model.showStats = true
                    } label: {
                        Label("Statistik", systemImage: "chart.bar.xaxis")
                    }
                }
                .controlSize(.large)
                .buttonStyle(.glass)
            }
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
                Button {
                    model.showLightroom = true
                } label: {
                    Label(model.lightroomDone ? "Erneut nach Lightroom übertragen" : "Behaltene Fotos nach Lightroom übertragen",
                          systemImage: "camera.aperture")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .controlSize(.extraLarge)
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
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
                        model.reopenSource()
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
