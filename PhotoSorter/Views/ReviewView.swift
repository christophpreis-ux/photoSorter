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
            VStack(spacing: 0) {
                ControlBar()
                Divider()
                HStack(spacing: 0) {
                    ColumnHeader(title: "Behalten", count: model.keptCount, symbol: "checkmark.circle.fill", color: .green)
                    Divider().frame(height: 22)
                    ColumnHeader(title: "Aussortieren", count: model.rejectedCount, symbol: "xmark.bin.fill", color: .red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
                Divider()
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
                        .padding(16)
                    }
                    .background(Color(nsColor: .underPageBackgroundColor))
                    .onChange(of: model.selectedChapterID) { _, id in
                        guard let id else { return }
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
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
            }
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

    /// K = behalten, X = aussortieren, A = automatisch, V = Szene vergleichen.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.isEmpty, let photo = model.selectedPhoto else { return .ignored }
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
        List(selection: $model.selectedChapterID) {
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
                    .tag(chapter.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.sortIntoChapterFolders
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
                    if model.sortIntoChapterFolders {
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
            .menuStyle(.borderedButton)
            .fixedSize()
            .help(chapter.topLabels.isEmpty ? "" : "Erkannt: " + chapter.topLabels.joined(separator: ", "))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
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
                    Text("Aussortier-Stärke")
                        .font(.headline)
                    Text(strictnessLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                HStack(spacing: 8) {
                    Text("Mild").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { model.strictness },
                        set: { value in withAnimation(decisionAnimation) { model.strictness = value } }
                    ), in: 0...1)
                    .frame(minWidth: 220, maxWidth: 380)
                    Text("Streng").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("In Ordner pro Abschnitt sortieren", isOn: $model.sortIntoChapterFolders)
                    .toggleStyle(.checkbox)
                    .help("z. B. „02 Trauung Kirche“, „03 Sektempfang“ – so kannst du in Lightroom pro Ordner ein Preset anwenden")
                Toggle("Dateinamen mit Kategorie versehen", isOn: $model.renameKept)
                    .toggleStyle(.checkbox)
                    .help("z. B. „Gruppenfoto_IMG_1234.jpg“ oder „Portrait_IMG_1234.jpg“")
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
                Label("Sortieren", systemImage: "tray.and.arrow.down.fill")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.rejectedCount == 0 && !model.renameKept && !model.sortIntoChapterFolders)
            .confirmationDialog("Fotos sortieren?", isPresented: $confirm) {
                Button("Jetzt sortieren") { model.apply() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("\(model.rejectedCount) Fotos (\(model.rejectedFileCount) Dateien) werden in den Unterordner „\(FileOrganizer.rejectFolderName)“ verschoben – es wird nichts gelöscht."
                     + (model.sortIntoChapterFolders ? " Die \(model.keptCount) behaltenen Fotos werden in \(model.chapters.count) Abschnitts-Ordner sortiert." : "")
                     + (model.renameKept ? " Dateinamen bekommen die Kategorie als Präfix." : ""))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var strictnessLabel: String {
        switch model.strictness {
        case ..<0.01: "nichts aussortieren"
        case ..<0.3: "nur klare Ausreißer"
        case ..<0.6: "ausgewogen"
        case ..<0.9: "streng"
        default: "nur das Beste je Szene"
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
