import SwiftUI

/// Alle Gruppenfotos, die kombiniert werden können – mit einem Klick übernehmen.
struct MergeQueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let queue = model.mergeQueue
        ScrollView {
            LazyVStack(spacing: 14) {
                if queue.isEmpty {
                    ContentUnavailableView("Nichts zu kombinieren", systemImage: "wand.and.stars",
                                           description: Text("Auf keinem besten Gruppenfoto hat jemand die Augen geschlossen."))
                        .padding(.top, 80)
                }
                ForEach(queue, id: \.scene.id) { item in
                    MergeQueueCard(scene: item.scene, candidate: item.candidate)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gruppenfotos kombinieren").font(.title3.bold())
                    Text("Auf dem besten Foto hat jemand die Augen zu? Das Gesicht wird aus einer anderen Aufnahme der Serie übernommen. "
                         + (model.isPhotosSource ? "Übernommene Fotos landen als neues Foto in Apple Fotos." : "Übernommene Fotos werden neben dem Original gespeichert."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    model.approveAllMerges()
                } label: {
                    Label("Alle übernehmen (\(model.openMergeCount))", systemImage: "checkmark.circle.fill")
                }
                .controlSize(.large)
                .buttonStyle(.glassProminent)
                .tint(Theme.keep)
                .disabled(model.openMergeCount == 0)
            }
            .padding(16)
            .glassPanel(cornerRadius: 24)
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .onAppear { model.prepareMerges() }
    }
}

private struct MergeQueueCard: View {
    @Environment(AppModel.self) private var model
    let scene: PhotoScene
    let candidate: MergeCandidate
    @State private var showOriginal = false

    var body: some View {
        let state = model.mergeStates[scene.id]
        HStack(alignment: .top, spacing: 16) {
            preview(state)
                .frame(width: 320, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomLeading) {
                    if case .ready = state {
                        Text(showOriginal ? "Original" : "Kombiniert")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: Capsule())
                            .padding(8)
                    }
                }
                .onHover { showOriginal = $0 }
                .help("Zum Vergleichen mit der Maus darüberfahren")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Szene \(scene.index)").font(.headline)
                    Text(scene.startDate.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                    Text("· \(candidate.swaps.count) \(candidate.swaps.count == 1 ? "Person" : "Personen")")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                faces(state)

                Spacer(minLength: 0)
                actions(state)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(borderColor(state), lineWidth: 1.5))
    }

    @ViewBuilder
    private func preview(_ state: MergeState?) -> some View {
        if case .ready(let result) = state, let image = showOriginal ? result.originalPreview : result.preview {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
        } else if let thumb = ThumbnailStore.image(for: candidate.base) {
            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                .overlay {
                    if case .working = state { ProgressView().controlSize(.large) }
                }
        } else {
            Rectangle().fill(Theme.surfaceRaised)
        }
    }

    @ViewBuilder
    private func faces(_ state: MergeState?) -> some View {
        switch state {
        case .ready(let result):
            HStack(spacing: 14) {
                ForEach(Array(result.faceCrops.enumerated()), id: \.offset) { _, crop in
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(decorative: crop.before, scale: 1).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.reject.opacity(0.7), lineWidth: 1.5))
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Image(decorative: crop.after, scale: 1).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.keep.opacity(0.8), lineWidth: 1.5))
                        }
                        Text("Person \(crop.personID + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        case .failed:
            Label("Nicht sauber kombinierbar – die Kopfhaltung ist zwischen den Aufnahmen zu unterschiedlich.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        case .saved:
            Label("Kombiniertes Foto gespeichert", systemImage: "checkmark.seal.fill")
                .font(.callout)
                .foregroundStyle(Theme.keep)
        case .working, .saving:
            Label(statusText(state), systemImage: "hourglass").font(.callout).foregroundStyle(.secondary)
        case nil:
            Label("Wartet auf Vorschau …", systemImage: "clock").font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(_ state: MergeState?) -> some View {
        HStack {
            switch state {
            case .saved:
                EmptyView()
            case .failed:
                Button("Ausblenden") { withAnimation { model.dismissMerge(scene) } }
                    .buttonStyle(.glass)
            default:
                Button {
                    model.approveMerge(scene)
                } label: {
                    if case .saving = state {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Übernehmen", systemImage: "checkmark")
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.keep)
                .controlSize(.large)
                Button("Überspringen") { withAnimation { model.dismissMerge(scene) } }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
            Spacer()
            Button {
                model.compareScene = scene
            } label: {
                Label("Alle Versionen", systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.borderless)
        }
    }

    private func statusText(_ state: MergeState?) -> String {
        switch state {
        case .working: "Erstelle Vorschau …"
        case .saving: "Speichere …"
        default: ""
        }
    }

    private func borderColor(_ state: MergeState?) -> Color {
        switch state {
        case .saved: Theme.keep.opacity(0.7)
        case .failed: Color.orange.opacity(0.5)
        default: Theme.stroke
        }
    }
}
