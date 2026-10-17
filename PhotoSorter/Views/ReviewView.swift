import SwiftUI

let decisionAnimation = Animation.spring(response: 0.55, dampingFraction: 0.78)

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var listFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            ChapterSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            Group {
                switch model.sidebarSelection {
                case .merge:
                    MergeQueueView()
                case .stats:
                    StatsView()
                default:
                    reviewList
                }
            }
            .navigationSplitViewColumnWidth(min: 560, ideal: 980)
        }
        .onChange(of: model.selectedPhotoID) { listFocused = true }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Filter", selection: $model.filter) {
                    ForEach(SceneFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                Slider(value: $model.thumbnailSize, in: 80...240) {
                    Text("Größe")
                } minimumValueLabel: {
                    Image(systemName: "photo").imageScale(.small)
                } maximumValueLabel: {
                    Image(systemName: "photo").imageScale(.large)
                }
                .frame(width: 140)
                .help("Vorschaugröße")
                GroupingSettingsButton()
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
            }
        }
    }

    private var reviewList: some View {
        @Bindable var model = model
        return Group {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                            ForEach(model.chapters) { chapter in
                                let scenes = model.filteredScenes(in: chapter)
                                if !scenes.isEmpty {
                                    Section {
                                        ForEach(scenes) { scene in
                                            SceneCard(scene: scene)
                                        }
                                    } header: {
                                        ChapterHeader(chapter: chapter)
                                            .id(chapter.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(Theme.background)
                    // Inhalte scrollen unter dem schwebenden Glas-Panel hindurch.
                    .safeAreaInset(edge: .top, spacing: 0) {
                        VStack(spacing: 10) {
                            ControlBar()
                            HStack(spacing: 12) {
                                ColumnHeader(title: "Verschont", count: model.keptCount, symbol: "shield.lefthalf.filled", color: Theme.keep)
                                ColumnHeader(title: "Terminieren", count: model.rejectedCount, symbol: "scope", color: Theme.reject)
                            }
                        }
                        .padding(14)
                        .frame(height: 132)
                        .glassPanel(cornerRadius: 24)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    }
                    .onChange(of: model.sidebarSelection, initial: true) { _, selection in
                        guard case .chapter(let id) = selection else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .top) }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($listFocused)
                .onKeyPress(phases: .down) { press in handleKey(press) }
            }
            .inspector(isPresented: $model.showInspector) {
                PhotoInspector()
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 520)
            }
    }

    /// Leertaste = Großansicht, ← → = blättern, K = behalten, X = aussortieren, A = automatisch, V = Szene vergleichen.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, let photo = model.selectedPhoto else { return .ignored }
        switch press.key {
        case .space:
            withAnimation(.easeOut(duration: 0.15)) { model.previewPhotoID = photo.id }
            return .handled
        case .leftArrow, .rightArrow:
            if let next = model.neighbor(of: photo, offset: press.key == .leftArrow ? -1 : 1) { model.selectedPhotoID = next.id }
            return .handled
        default:
            break
        }
        switch press.characters.lowercased() {
        case "k": withAnimation(decisionAnimation) { model.setOverride(true, for: photo) }
        case "x": withAnimation(decisionAnimation) { model.setOverride(false, for: photo) }
        case "a": withAnimation(decisionAnimation) { model.setOverride(nil, for: photo) }
        case "v": model.compareScene = model.scene(of: photo)
        default: return .ignored
        }
        return .handled
    }
}

/// Liste der erkannten Abschnitte (Trauung, Sektempfang …) zum Springen.
struct ChapterSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section("Werkzeuge") {
                HStack {
                    Label("Kombinieren", systemImage: "wand.and.stars")
                    Spacer()
                    if model.openMergeCount > 0 {
                        Text("\(model.openMergeCount)")
                            .font(.caption.bold().monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.85), in: Capsule())
                    }
                }
                .tag(SidebarItem.merge)
                Label("Statistik", systemImage: "chart.bar.xaxis")
                    .tag(SidebarItem.stats)
            }
            Section("Abschnitte") {
                ForEach(model.chapters) { chapter in
                    let counts = model.photoCount(of: chapter)
                    HStack {
                        Label(chapter.name, systemImage: chapter.kind.symbol)
                            .lineLimit(1)
                        Spacer()
                        Text("\(counts.kept)/\(counts.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarItem.chapter(chapter.id))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.isPhotosSource
                 ? "Aussortierte Fotos werden in „Zuletzt gelöscht“ verschoben. Favoriten bleiben immer erhalten."
                 : model.sortIntoChapterFolders
                 ? "Behaltene Fotos werden in Ordner pro Abschnitt sortiert – ideal für Lightroom-Presets."
                 : "Behaltene Fotos bleiben im Hauptordner.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }
}

/// Überschrift eines Abschnitts: Name (editierbar), Art, Zielordner.
struct ChapterHeader: View {
    @Environment(AppModel.self) private var model
    let chapter: EventChapter
    @State private var name = ""

    var body: some View {
        let counts = model.photoCount(of: chapter)
        let scenes = model.scenes(in: chapter)
        HStack(spacing: 12) {
            Image(systemName: chapter.kind.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name des Abschnitts", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title3.bold())
                    .onSubmit { model.renameChapter(chapter.id, to: name) }
                    .onChange(of: chapter.name) { _, new in name = new }
                HStack(spacing: 6) {
                    if let first = scenes.first?.startDate, let last = scenes.last?.photos.last?.captureDate {
                        Text("\(first.formatted(date: .abbreviated, time: .shortened)) – \(last.formatted(date: .omitted, time: .shortened))")
                    }
                    Text("· \(counts.total) Fotos · \(counts.kept) behalten")
                    if model.sortIntoChapterFolders && !model.isPhotosSource {
                        Label(model.folderName(for: chapter), systemImage: "folder")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Art", selection: Binding(get: { chapter.kind }, set: { model.setKind($0, for: chapter.id) })) {
                    ForEach(EventKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Mit vorherigem Abschnitt zusammenführen") {
                    withAnimation { model.mergeWithPrevious(chapter.id) }
                }
                .disabled(model.chapters.first?.id == chapter.id)
            } label: {
                Label(chapter.kind.title, systemImage: "tag")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .help(chapter.topLabels.isEmpty ? "" : "Erkannt: " + chapter.topLabels.joined(separator: ", "))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassPanel(cornerRadius: 18)
        .onAppear { name = chapter.name }
    }
}

private struct ColumnHeader: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(color)
                .font(.headline)
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Schieberegler für die Aussortier-Stärke und der Aussortieren-Button.
struct ControlBar: View {
    @Environment(AppModel.self) private var model
    @State private var confirm = false

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Terminator-Modus")
                        .font(.headline)
                    Text(strictnessLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                HStack(spacing: 8) {
                    Text("Gnädig").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { model.strictness },
                        set: { value in withAnimation(decisionAnimation) { model.strictness = value } }
                    ), in: 0...1)
                    .frame(minWidth: 220, maxWidth: 380)
                    Text("Gnadenlos").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                if model.isPhotosSource {
                    Label("\(model.favoriteCount) Favoriten geschützt", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.callout)
                } else {
                    Toggle("In Ordner pro Abschnitt sortieren", isOn: $model.sortIntoChapterFolders)
                        .toggleStyle(.checkbox)
                        .lineLimit(1)
                        .help("z. B. „02 Trauung Kirche“, „03 Sektempfang“ – so kannst du in Lightroom pro Ordner ein Preset anwenden")
                    Toggle("Dateinamen mit Kategorie versehen", isOn: $model.renameKept)
                        .toggleStyle(.checkbox)
                        .lineLimit(1)
                        .help("z. B. „Gruppenfoto_IMG_1234.jpg“ oder „Portrait_IMG_1234.jpg“")
                }
                if model.hasOverrides {
                    Button("Manuelle Änderungen zurücksetzen") {
                        withAnimation(decisionAnimation) { model.resetOverrides() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Button {
                confirm = true
            } label: {
                Label(model.isPhotosSource ? "Terminieren (Papierkorb)" : "Terminieren",
                      systemImage: "scope")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .tint(Theme.reject)
            .disabled(model.isPhotosSource ? model.rejectedCount == 0
                      : model.rejectedCount == 0 && !model.renameKept && !model.sortIntoChapterFolders)
            .confirmationDialog("\(model.rejectedCount) Ziele terminieren?", isPresented: $confirm) {
                Button(model.isPhotosSource ? "\(model.rejectedCount) Fotos löschen" : "Terminieren",
                       role: model.isPhotosSource ? .destructive : nil) { model.apply() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                if model.isPhotosSource {
                    Text("\(model.rejectedCount) Fotos werden in Apple Fotos nach „Zuletzt gelöscht“ verschoben und sind dort 30 Tage wiederherstellbar. \(model.favoriteCount) Favoriten werden nicht angetastet.")
                } else {
                Text("\(model.rejectedCount) Fotos (\(model.rejectedFileCount) Dateien) werden in den Unterordner „\(FileOrganizer.rejectFolderName)“ verschoben – es wird nichts gelöscht."
                     + (model.sortIntoChapterFolders ? " Die \(model.keptCount) behaltenen Fotos werden in \(model.chapters.count) Abschnitts-Ordner sortiert." : "")
                     + (model.renameKept ? " Dateinamen bekommen die Kategorie als Präfix." : ""))
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private var strictnessLabel: String {
        switch model.strictness {
        case ..<0.01: "Pazifist – niemand wird terminiert"
        case ..<0.3: "Beschützer – nur klare Ausreißer"
        case ..<0.6: "Kampfmodus – ausgewogen"
        case ..<0.9: "T-1000 – streng"
        default: "Judgment Day – nur das Beste überlebt"
        }
    }
}

struct GroupingSettingsButton: View {
    @Environment(AppModel.self) private var model
    @State private var show = false

    var body: some View {
        @Bindable var model = model
        Button {
            show.toggle()
        } label: {
            Label("Szenen-Erkennung", systemImage: "rectangle.3.group")
        }
        .help("Wie Fotos zu Szenen zusammengefasst werden")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            Form {
                Section("Szenen-Erkennung") {
                    VStack(alignment: .leading) {
                        Text("Ähnlichkeit: \(similarityLabel)")
                        Slider(value: Binding(
                            get: { Double(model.grouping.similarityThreshold) },
                            set: { model.grouping.similarityThreshold = Float($0) }
                        ), in: 0.25...0.8) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("eng").font(.caption)
                        } maximumValueLabel: {
                            Text("locker").font(.caption)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Max. Abstand innerhalb einer Szene: \(Int(model.grouping.sceneGap)) s")
                        Slider(value: $model.grouping.sceneGap, in: 10...900, step: 10)
                    }
                    VStack(alignment: .leading) {
                        Text("Serienbild bis: \(model.grouping.burstGap, specifier: "%.1f") s")
                        Slider(value: $model.grouping.burstGap, in: 0.5...10, step: 0.5)
                    }
                }
                Section("Abschnitte") {
                    VStack(alignment: .leading) {
                        Text("Neuer Abschnitt nach Pause von: \(Int(model.grouping.chapterGap / 60)) min")
                        Slider(value: $model.grouping.chapterGap, in: 120...3600, step: 60)
                    }
                    Button("Abschnitte neu erkennen") { model.detectChapters() }
                }
            }
            .formStyle(.grouped)
            .frame(width: 340)
        }
    }

    private var similarityLabel: String {
        switch model.grouping.similarityThreshold {
        case ..<0.4: "nur sehr ähnliche"
        case ..<0.6: "normal"
        default: "großzügig"
        }
    }
}
