import SwiftUI

let decisionAnimation = Animation.spring(response: 0.55, dampingFraction: 0.78)

struct ReviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
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
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.filteredScenes) { scene in
                        SceneCard(scene: scene)
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .inspector(isPresented: $model.showInspector) {
            PhotoInspector()
                .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
        }
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

            VStack(alignment: .trailing, spacing: 6) {
                Toggle("Behaltene nach Kategorie umbenennen", isOn: $model.renameKept)
                    .toggleStyle(.checkbox)
                    .help("z. B. „Gruppenfoto_IMG_1234.jpg“ oder „Portrait_IMG_1234.jpg“ – im selben Ordner")
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
                Label("Aussortieren", systemImage: "tray.and.arrow.down.fill")
                    .padding(.horizontal, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.rejectedCount == 0 && !model.renameKept)
            .confirmationDialog("Fotos aussortieren?", isPresented: $confirm) {
                Button("\(model.rejectedCount) Fotos verschieben") { model.apply() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("\(model.rejectedCount) Fotos (\(model.rejectedFileCount) Dateien) werden in den Unterordner „\(FileOrganizer.rejectFolderName)“ verschoben – es wird nichts gelöscht."
                     + (model.renameKept ? " Die \(model.keptCount) behaltenen Fotos werden nach Kategorie umbenannt." : ""))
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
