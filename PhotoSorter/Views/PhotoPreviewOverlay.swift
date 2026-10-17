import SwiftUI

/// Großansicht (Leertaste): Foto bildschirmfüllend, blättern mit ← →, K/X entscheiden, Leertaste/Esc schließt.
struct PhotoPreviewOverlay: View {
    @Environment(AppModel.self) private var model
    let photo: PhotoItem
    @State private var image: CGImage?
    @State private var showFaces = false
    @FocusState private var focused: Bool

    var body: some View {
        let decision = model.decisions[photo.id]
        let evaluation = model.scene(of: photo).flatMap { model.evaluations[$0.id]?.evaluations[photo.id] }

        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture { close() }

            Group {
                if showFaces {
                    FaceOverlayImage(photo: photo, image: image, faces: evaluation?.faces ?? [])
                } else if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else if let thumb = ThumbnailStore.image(for: photo) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                        .overlay { ProgressView().controlSize(.large) }
                }
            }
            .padding(.horizontal, 60)
            .padding(.top, 30)
            .padding(.bottom, 110)
            .id(photo.id)
            .transition(.opacity)

            HStack {
                navButton("chevron.left", offset: -1)
                Spacer()
                navButton("chevron.right", offset: 1)
            }
            .padding(.horizontal, 14)

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if decision?.isFavorite == true { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                            if decision?.isBest == true { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                            Text(photo.baseName).font(.headline).lineLimit(1)
                        }
                        Text(decision?.reason ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 380, alignment: .leading)

                    if let issues = decision?.issues, !issues.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(PhotoIssue.allCases.filter(issues.contains), id: \.self) { issue in
                                Image(systemName: issue.symbol).help(issue.title)
                            }
                        }
                        .foregroundStyle(.orange)
                    }

                    Spacer()

                    Toggle(isOn: $showFaces) { Label("Gesichter", systemImage: "face.dashed") }
                        .toggleStyle(.button)
                        .buttonStyle(.glass)

                    Button {
                        set(true)
                    } label: {
                        Label("Behalten (K)", systemImage: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(decision?.keep == true ? Theme.keep : .gray)

                    Button {
                        set(false)
                    } label: {
                        Label("Aussortieren (X)", systemImage: "xmark.bin")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(decision?.keep == false ? Theme.reject : .gray)
                    .disabled(photo.isFavorite)
                }
                .padding(.horizontal, 18)
                .frame(height: 64)
                .glassPanel(cornerRadius: 22)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .task(id: photo.id) {
            image = nil
            image = await PreviewLoader.load(photo.primaryURL, maxPixel: 2600)
        }
    }

    private func navButton(_ symbol: String, offset: Int) -> some View {
        Button {
            step(offset)
        } label: {
            Image(systemName: symbol)
                .font(.title2.bold())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(model.neighbor(of: photo, offset: offset) == nil)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .space, .escape: close(); return .handled
        case .leftArrow: step(-1); return .handled
        case .rightArrow: step(1); return .handled
        default: break
        }
        switch press.characters.lowercased() {
        case "k": set(true)
        case "x": set(false)
        case "a": withAnimation(decisionAnimation) { model.setOverride(nil, for: photo) }
        case "f": showFaces.toggle()
        default: return .ignored
        }
        return .handled
    }

    private func set(_ keep: Bool) {
        withAnimation(decisionAnimation) { model.setOverride(keep, for: photo) }
    }

    private func step(_ offset: Int) {
        guard let next = model.neighbor(of: photo, offset: offset) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            model.previewPhotoID = next.id
            model.selectedPhotoID = next.id
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) { model.previewPhotoID = nil }
    }
}
