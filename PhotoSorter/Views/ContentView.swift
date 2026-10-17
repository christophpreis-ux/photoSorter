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
            if model.showTerminatedBurst {
                TerminatedBurst(count: model.lastResult?.rejectedPhotos ?? model.lastPhotosDeleted ?? 0,
                                isPresented: $model.showTerminatedBurst)
                    .transition(.opacity)
            }
        }
        .overlay {
            if model.phase == .review, let photo = model.previewPhoto {
                PhotoPreviewOverlay(photo: photo)
                    .transition(.opacity)
            }
        }
        .navigationTitle(model.source?.title ?? "Photo Terminator")
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
            if UserDefaults.standard.bool(forKey: "demoBurst") { model.showTerminatedBurst = true }
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
        case .analyzing: "Zielerfassung …"
        default: ""
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var totalRejected = 0
    @State private var welcomeQuote = TerminatorQuotes.random(TerminatorQuotes.welcome)

    var body: some View {
        VStack(spacing: 22) {
            RedEye(size: 90)
                .padding(-30)
            VStack(spacing: 10) {
                GlitchText(text: "PHOTO TERMINATOR", font: .system(size: 44, weight: .black, design: .rounded))
                Text(welcomeQuote)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(HUD.red)
                    .multilineTextAlignment(.center)
                Text("Findet ähnliche Fotos, erkennt geschlossene Augen und Unschärfe\nund terminiert den Rest – komplett auf deinem Mac.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    model.chooseFolder()
                } label: {
                    Label("Mission starten: Ordner", systemImage: "scope")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                Button {
                    model.showPhotosPicker = true
                } label: {
                    Label("Apple Fotos infiltrieren", systemImage: "photo.on.rectangle.angled")
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
                Label(totalRejected > 0 ? "Rang \(TerminatorRank.title(for: totalRejected)) · \(totalRejected.formatted()) Fotos terminiert" : "Statistik",
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
                RedEye(size: 70)
                Text("SUCHE ZIELE …").font(.system(.title3, design: .monospaced).weight(.bold)).foregroundStyle(HUD.red)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    HUDScanner(image: model.hudImage, lines: model.hudLines)
                        .frame(width: 420, height: 300)
                    VStack(alignment: .leading, spacing: 10) {
                        GlitchText(text: "ZIELERFASSUNG", font: .system(size: 26, weight: .black, design: .rounded))
                        Text("Schärfe · Augen · Gesichter · Belichtung · Ähnlichkeit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(model.hudLog.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.contains("⚠︎") ? HUD.red : .secondary)
                                    .opacity(0.4 + 0.6 * Double(index + 1) / Double(max(model.hudLog.count, 1)))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                    .frame(width: 300, height: 300)
                }
                FlameProgressBar(progress: Double(model.progressDone) / Double(max(model.progressTotal, 1)))
                    .frame(width: 740)
                Text("\(model.progressDone) von \(model.progressTotal) Zielen analysiert\(eta)")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                QuoteTicker(quotes: TerminatorQuotes.analysis)
                    .frame(width: 640, height: 44)
            }
            Button("Mission abbrechen", role: .cancel) { model.cancelAnalysis() }
                .buttonStyle(.glass)
        }
        .padding(36)
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
    @State private var appliedQuote = TerminatorQuotes.random(TerminatorQuotes.applied)

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "scope")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(HUD.red)
                .shadow(color: HUD.red, radius: 12)
            GlitchText(text: "MISSION ERFÜLLT", font: .system(size: 40, weight: .black, design: .rounded))
            Text(appliedQuote)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(HUD.red)
            if let deleted = model.lastPhotosDeleted {
                VStack(spacing: 6) {
                    Text("\(deleted) Fotos terminiert – sie liegen in Apple Fotos unter „Zuletzt gelöscht“.")
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
                    Text("\(result.rejectedPhotos) Fotos wurden terminiert – also in den Ordner „\(FileOrganizer.rejectFolderName)“ verschoben.")
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
