import SwiftUI

/// Auswahl eines Presets: Standard übernehmen, kein Preset oder ein bestimmtes.
enum PresetChoice: Hashable {
    case useDefault
    case none
    case preset(String)
}

/// Schritt 4: behaltene Fotos mit Presets nach Lightroom übertragen.
struct LightroomExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var installed: [LightroomPreset] = []
    @State private var defaultPresetID: String? = LightroomPresets.builtIn("natural").id
    @State private var choices: [UUID: PresetChoice] = [:]
    @State private var addKeywords = true
    @State private var working = false
    @State private var progress = 0
    @State private var report: LightroomReport?
    @State private var info: String?
    private let app = LightroomApp.installed

    private var allPresets: [LightroomPreset] { LightroomPresets.builtIn + installed }
    private func preset(_ id: String?) -> LightroomPreset? { id.flatMap { id in allPresets.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let report {
                result(report)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        defaultSection
                        chapterSection
                        Toggle("Abschnitt und Kategorie als Stichwörter setzen (z. B. „Sektempfang“, „Porträt“)", isOn: $addKeywords)
                        infoBox
                    }
                    .padding(20)
                }
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 680)
        .background(Theme.background)
        .task { load() }
    }

    // MARK: Abschnitte

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "camera.aperture")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("In Lightroom übertragen").font(.title2.bold())
                Text("\(model.keptCount) behaltene Fotos · Presets pro Abschnitt – Vorschläge sind bereits ausgewählt.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(app?.name ?? "Lightroom nicht gefunden", systemImage: app == nil ? "exclamationmark.triangle" : "checkmark.seal.fill")
                .font(.callout)
                .foregroundStyle(app == nil ? .orange : Theme.keep)
        }
        .padding(20)
    }

    private var defaultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standard-Preset für alle").font(.headline)
            HStack {
                presetMenu(selection: Binding(get: { defaultPresetID.map { .preset($0) } ?? .none },
                                              set: { if case .preset(let id) = $0 { defaultPresetID = id } else { defaultPresetID = nil } }),
                           allowDefault: false)
                    .frame(width: 320)
                Text("Gilt für alle Abschnitte, für die nichts anderes gewählt ist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preset pro Abschnitt").font(.headline)
            VStack(spacing: 0) {
                ForEach(model.chapters) { chapter in
                    let suggestion = LightroomPresets.suggestion(for: chapter.kind, among: installed)
                    let choice = choices[chapter.id] ?? .useDefault
                    HStack(spacing: 12) {
                        Image(systemName: chapter.kind.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chapter.name).lineLimit(1)
                            Text("\(model.photoCount(of: chapter).kept) Fotos · \(chapter.kind.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if choice == .preset(suggestion.id) {
                            Label("Vorschlag", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        } else {
                            Button("Vorschlag: \(suggestion.name)") { choices[chapter.id] = .preset(suggestion.id) }
                                .buttonStyle(.link)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        presetMenu(selection: Binding(get: { choice }, set: { choices[chapter.id] = $0 }), allowDefault: true)
                            .frame(width: 250)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    Divider().padding(.leading, 50)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func presetMenu(selection: Binding<PresetChoice>, allowDefault: Bool) -> some View {
        Picker("", selection: selection) {
            if allowDefault {
                Text("Standard (\(preset(defaultPresetID)?.name ?? "kein Preset"))").tag(PresetChoice.useDefault)
            }
            Text("Kein Preset").tag(PresetChoice.none)
            Section("PhotoSorter-Vorschläge") {
                ForEach(LightroomPresets.builtIn) { Text($0.name).tag(PresetChoice.preset($0.id)) }
            }
            ForEach(Dictionary(grouping: installed, by: \.group).sorted(by: { $0.key < $1.key }), id: \.key) { group, presets in
                Section(group) {
                    ForEach(presets) { Text($0.name).tag(PresetChoice.preset($0.id)) }
                }
            }
        }
        .labelsHidden()
    }

    private var infoBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("RAW-Dateien bekommen eine XMP-Begleitdatei, JPEG/HEIC die Einstellungen verlustfrei in den Metadaten. Lightroom übernimmt sie beim Import automatisch.",
                  systemImage: "info.circle")
            Label(installed.isEmpty
                  ? "Keine eigenen Lightroom-Presets gefunden – die PhotoSorter-Vorschläge funktionieren trotzdem."
                  : "\(installed.count) eigene Lightroom-Presets gefunden. Passende werden automatisch vorgeschlagen.",
                  systemImage: "slider.horizontal.3")
            Button("PhotoSorter-Vorschläge auch in Lightroom als Presets installieren") {
                do {
                    let folder = try LightroomPresets.installBuiltIns()
                    info = "Installiert in \(folder.path) – nach einem Neustart von Lightroom unter „PhotoSorter“ verfügbar."
                } catch {
                    info = "Installation fehlgeschlagen: \(error.localizedDescription)"
                }
            }
            .buttonStyle(.link)
            if let info { Text(info).font(.caption).foregroundStyle(.secondary) }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(14)
        .background(Theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
    }

    private func result(_ report: LightroomReport) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.keep)
            Text("Presets angewendet").font(.title.bold())
            Text("\(report.photos) Fotos · \(report.sidecars) XMP-Begleitdateien · \(report.embedded) Dateien mit eingebetteten Einstellungen")
                .foregroundStyle(.secondary)
            if app != nil {
                Text("Lightroom zeigt jetzt den Import-Dialog mit den behaltenen Fotos – einfach „Importieren“ klicken.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Lightroom ist auf diesem Mac nicht installiert. Importiere die Abschnitts-Ordner später – die Einstellungen werden dann übernommen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if !report.skipped.isEmpty {
                DisclosureGroup("\(report.skipped.count) Dateien übersprungen") {
                    ScrollView { Text(report.skipped.joined(separator: "\n")).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(height: 100)
                }
                .frame(width: 480)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if working {
                ProgressView(value: Double(progress), total: Double(max(model.keptCount, 1)))
                    .frame(width: 240)
                Text("\(progress) von \(model.keptCount)").monospacedDigit().foregroundStyle(.secondary)
            }
            Spacer()
            if report != nil {
                if let folder = model.folderURL {
                    Button("Im Finder zeigen") { model.revealInFinder(folder) }.buttonStyle(.glass)
                }
                if app != nil {
                    Button("Erneut in Lightroom öffnen") { LightroomApp.open(model.lightroomOpenURLs()) }.buttonStyle(.glass)
                }
                Button("Fertig") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button(app != nil ? "Presets anwenden & in Lightroom öffnen" : "Presets anwenden") { run() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
        }
        .padding(16)
    }

    // MARK: Ablauf

    private func load() {
        installed = LightroomPresets.installed()
        for chapter in model.chapters where choices[chapter.id] == nil {
            choices[chapter.id] = .preset(LightroomPresets.suggestion(for: chapter.kind, among: installed).id)
        }
    }

    private func run() {
        let defaultPreset = preset(defaultPresetID)
        let resolved: [UUID: LightroomPreset?] = Dictionary(uniqueKeysWithValues: model.chapters.map { chapter in
            switch choices[chapter.id] ?? .useDefault {
            case .useDefault: (chapter.id, defaultPreset)
            case .none: (chapter.id, nil)
            case .preset(let id): (chapter.id, preset(id))
            }
        })
        let items = model.lightroomItems(defaultPreset: defaultPreset,
                                         presetForChapter: { resolved[$0.id] ?? defaultPreset },
                                         addKeywords: addKeywords)
        let openURLs = model.lightroomOpenURLs()
        working = true
        progress = 0
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                LightroomExporter.apply(items) { done in
                    Task { @MainActor in progress = done }
                }
            }.value
            working = false
            self.report = report
            model.lightroomDone = true
            LightroomApp.open(openURLs)
        }
    }
}

/// Schritt-Anzeige: Scannen → Auswählen → Aussortieren → Lightroom.
struct StepIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let steps = model.isPhotosSource ? ["Zielerfassung", "Auswahl", "Terminieren"]
                                         : ["Zielerfassung", "Auswahl", "Terminieren", "Lightroom"]
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let state = state(for: index)
                HStack(spacing: 5) {
                    ZStack {
                        Circle().fill(state == .done ? Theme.keep : state == .active ? Theme.accent : Color.white.opacity(0.12))
                        if state == .done {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        } else {
                            Text("\(index + 1)").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(title)
                        .font(.caption.weight(state == .active ? .semibold : .regular))
                        .foregroundStyle(state == .upcoming ? .secondary : .primary)
                }
                if index < steps.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 14, height: 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .fixedSize()
    }

    private enum StepState { case done, active, upcoming }

    private func state(for index: Int) -> StepState {
        let current: Int
        switch model.phase {
        case .idle: return .upcoming
        case .scanning, .analyzing: current = 0
        case .review: current = 1
        case .applied: current = model.lightroomDone ? 4 : (model.isPhotosSource ? 3 : 3)
        }
        if model.phase == .applied && model.isPhotosSource { return .done }
        return index < current ? .done : index == current ? .active : .upcoming
    }
}
