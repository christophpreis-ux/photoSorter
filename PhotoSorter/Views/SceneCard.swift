import SwiftUI

/// Eine Szene: links die behaltenen, rechts die aussortierten Fotos.
/// Ändert sich eine Entscheidung, fliegt das Foto per matchedGeometryEffect auf die andere Seite.
struct SceneCard: View {
    @Environment(AppModel.self) private var model
    let scene: PhotoScene
    @Namespace private var namespace

    var body: some View {
        let kept = scene.photos
            .filter { model.decisions[$0.id]?.keep != false }
            .sorted { (model.decisions[$0.id]?.score ?? 0) > (model.decisions[$1.id]?.score ?? 0) }
        let rejected = scene.photos.filter { model.decisions[$0.id]?.keep == false }

        VStack(alignment: .leading, spacing: 0) {
            header(kept: kept.count)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                side(kept, keep: true)
                Divider()
                side(rejected, keep: false)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
    }

    private func header(kept: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: scene.category.symbol)
                .foregroundStyle(.tint)
            Text("Szene \(scene.index)")
                .font(.headline)
            Text(scene.startDate.formatted(date: .abbreviated, time: .standard))
                .foregroundStyle(.secondary)
            Text("· \(scene.photos.count) \(scene.photos.count == 1 ? "Foto" : "Fotos") · \(scene.category.title)")
                .foregroundStyle(.secondary)
            if let evaluation = model.evaluations[scene.id], evaluation.isGroupScene {
                let people = evaluation.tracks.filter(\.isSignificant).count
                Label("\(people) Personen", systemImage: "person.2.fill")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            Spacer()
            if model.mergeCandidate(for: scene) != nil {
                Button {
                    model.compareScene = scene
                } label: {
                    Label("Augen-zu kombinieren", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderless)
                .help("Auf dem besten Foto hat jemand die Augen zu – aus einem anderen Foto der Serie kann das Gesicht übernommen werden")
            }
            if scene.photos.count > 1 {
                Button {
                    model.compareScene = scene
                } label: {
                    Label("Vergleichen", systemImage: "rectangle.split.3x1")
                }
                .buttonStyle(.borderless)
            }
            Menu {
                Button("Neuer Abschnitt ab dieser Szene") {
                    withAnimation { model.splitChapter(at: scene) }
                }
                .disabled(model.chapter(of: scene)?.sceneIDs.first == scene.id)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func side(_ photos: [PhotoItem], keep: Bool) -> some View {
        let size = model.thumbnailSize
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(photos) { photo in
                PhotoThumbView(photo: photo, size: size)
                    .matchedGeometryEffect(id: photo.id, in: namespace)
                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: size * 0.75, alignment: .topLeading)
        .overlay {
            if photos.isEmpty {
                Text(keep ? "Nichts behalten" : "Nichts aussortiert")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(keep ? Theme.keepArea : Theme.rejectArea)
        .overlay(alignment: .leading) {
            Rectangle().fill((keep ? Theme.keep : Theme.reject).opacity(0.6)).frame(width: 3)
        }
    }
}

struct PhotoThumbView: View {
    @Environment(AppModel.self) private var model
    let photo: PhotoItem
    let size: CGFloat

    var body: some View {
        let decision = model.decisions[photo.id]
        let selected = model.selectedPhotoID == photo.id

        ZStack {
            if let image = ThumbnailStore.image(for: photo) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: size, height: size * 0.75)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .saturation(decision?.keep == false ? 0.5 : 1)
        .opacity(decision?.keep == false ? 0.8 : 1)
        .overlay(alignment: .topLeading) {
            if decision?.isBest == true {
                badge(Image(systemName: "star.fill"), color: .yellow)
            }
        }
        .overlay(alignment: .topTrailing) {
            if decision?.isManual == true {
                badge(Image(systemName: "hand.raised.fill"), color: .white)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let issues = decision?.issues, !issues.isEmpty {
                HStack(spacing: 3) {
                    ForEach(PhotoIssue.allCases.filter(issues.contains), id: \.self) { issue in
                        Image(systemName: issue.symbol)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                .padding(4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if photo.hasRaw {
                Text("RAW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 3)
        }
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(decisionAnimation) { model.toggle(photo) }
        }
        .onTapGesture {
            model.selectedPhotoID = photo.id
            model.showInspector = true
        }
        .contextMenu {
            Button("Behalten") { withAnimation(decisionAnimation) { model.setOverride(true, for: photo) } }
            Button("Aussortieren") { withAnimation(decisionAnimation) { model.setOverride(false, for: photo) } }
            Button("Automatisch entscheiden") { withAnimation(decisionAnimation) { model.setOverride(nil, for: photo) } }
            Divider()
            Button("Szene vergleichen") { model.compareScene = model.scene(of: photo) }
            Button("Im Finder zeigen") { model.revealInFinder(photo.primaryURL) }
        }
        .help(decision.map { "\($0.reason)\nDoppelklick zum Umschalten" } ?? photo.baseName)
    }

    private func badge(_ image: Image, color: Color) -> some View {
        image
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(4)
            .background(.black.opacity(0.5), in: Circle())
            .padding(4)
    }
}
