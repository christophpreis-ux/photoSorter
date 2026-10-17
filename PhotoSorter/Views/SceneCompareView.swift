import SwiftUI

/// Vergleich aller Versionen einer Szene – mit Gesichtern pro Person,
/// damit man sieht, auf welchem Foto wer gut aussieht.
struct SceneCompareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scene: PhotoScene
    @State private var images: [UUID: CGImage] = [:]
    @State private var showAll = false

    var body: some View {
        let evaluation = model.evaluations[scene.id]
        let kept = scene.photos.filter { model.decisions[$0.id]?.keep != false }
        let shown = showAll ? scene.photos : kept
        let people = evaluation?.tracks.filter(\.isSignificant) ?? []

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Szene \(scene.index) vergleichen").font(.title2.bold())
                    Text("\(kept.count) von \(scene.photos.count) Fotos werden behalten")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $showAll) {
                    Text("Behaltene").tag(false)
                    Text("Alle Versionen").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(shown) { photo in
                                CompareCard(photo: photo, image: images[photo.id], evaluation: evaluation)
                            }
                        }
                        .padding(.horizontal)
                        .animation(decisionAnimation, value: shown.map(\.id))
                    }

                    if !people.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Personen").font(.title3.bold())
                            Text("Für jede Person wird mindestens eine Version behalten, auf der sie gut aussieht. ★ = beste Aufnahme der Person.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
                                    GridRow {
                                        Text("")
                                        ForEach(scene.photos) { photo in
                                            let keep = model.decisions[photo.id]?.keep != false
                                            Image(systemName: keep ? "checkmark.circle.fill" : "xmark.circle")
                                                .foregroundStyle(keep ? .green : .secondary)
                                        }
                                    }
                                    ForEach(people) { person in
                                        GridRow {
                                            Text("Person \(person.id + 1)")
                                                .font(.callout.bold())
                                                .gridColumnAlignment(.leading)
                                            ForEach(scene.photos) { photo in
                                                FaceCell(photo: photo, person: person, image: images[photo.id],
                                                         evaluation: evaluation?.evaluations[photo.id],
                                                         kept: model.decisions[photo.id]?.keep != false)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
        .frame(minWidth: 960, idealWidth: 1200, minHeight: 660, idealHeight: 820)
        .task {
            await withTaskGroup(of: (UUID, CGImage?).self) { group in
                for photo in scene.photos {
                    let url = photo.primaryURL, id = photo.id
                    group.addTask { (id, await PreviewLoader.load(url, maxPixel: 1600)) }
                }
                for await (id, image) in group {
                    if let image { images[id] = image }
                }
            }
        }
    }
}

private struct CompareCard: View {
    @Environment(AppModel.self) private var model
    let photo: PhotoItem
    let image: CGImage?
    let evaluation: SceneEvaluation?

    var body: some View {
        let decision = model.decisions[photo.id]
        VStack(alignment: .leading, spacing: 8) {
            FaceOverlayImage(photo: photo, image: image, faces: evaluation?.evaluations[photo.id]?.faces ?? [])
                .frame(height: 380)
                .opacity(decision?.keep == false ? 0.6 : 1)
            HStack {
                if decision?.isBest == true { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                Text(photo.baseName).font(.caption.bold()).lineLimit(1)
                Spacer()
                Text("\(Int((decision?.score ?? 0) * 100))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(decision?.reason ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button {
                withAnimation(decisionAnimation) { model.toggle(photo) }
            } label: {
                Label(decision?.keep == false ? "Doch behalten" : "Aussortieren",
                      systemImage: decision?.keep == false ? "arrow.uturn.left" : "xmark.bin")
                    .frame(maxWidth: .infinity)
            }
            .tint(decision?.keep == false ? .green : .red)
        }
        .frame(width: 380 * aspect)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(decision?.keep == false ? Color.red.opacity(0.5) : Color.green.opacity(0.6), lineWidth: 2))
    }

    private var aspect: CGFloat {
        guard let size = photo.analysis?.pixelSize, size.height > 0 else { return 1.5 }
        return min(max(size.width / size.height, 0.6), 1.8)
    }
}

private struct FaceCell: View {
    let photo: PhotoItem
    let person: PersonTrack
    let image: CGImage?
    let evaluation: PhotoEvaluation?
    let kept: Bool

    var body: some View {
        if let faceIndex = person.faceIndexByPhoto[photo.id], let face = photo.analysis?.faces[faceIndex] {
            let faceEval = evaluation?.faces.first { $0.trackID == person.id }
            let good = person.goodPhotos.contains(photo.id)
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let crop = crop(face.boundingBox) {
                        Image(decorative: crop, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(kept ? 1 : 0.55)
                HStack(spacing: 2) {
                    if person.bestPhoto == photo.id { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    if faceEval?.eyesClosed == true { Image(systemName: "eye.slash.fill").foregroundStyle(.red) }
                }
                .font(.system(size: 10, weight: .bold))
                .padding(3)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(3)
            }
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(good && kept ? Color.green : good ? Color.orange : Color.clear, lineWidth: 2))
            .help(good ? "Person \(person.id + 1) sieht hier gut aus" : "")
        } else {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4]))
                .frame(width: 84, height: 84)
        }
    }

    private func crop(_ box: CGRect) -> CGImage? {
        guard let image else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let size = max(box.width * w, box.height * h) * 1.5
        let rect = CGRect(x: box.midX * w - size / 2, y: (1 - box.midY) * h - size / 2, width: size, height: size)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return image.cropping(to: rect)
    }
}
