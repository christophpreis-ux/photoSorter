import SwiftUI

struct PhotoInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let photo = model.selectedPhoto {
            PhotoDetail(photo: photo)
                .id(photo.id)
        } else {
            ContentUnavailableView("Kein Foto ausgewählt", systemImage: "photo",
                                   description: Text("Klicke auf ein Foto, um Details zu sehen."))
        }
    }
}

private struct PhotoDetail: View {
    @Environment(AppModel.self) private var model
    let photo: PhotoItem
    @State private var preview: CGImage?

    var body: some View {
        let decision = model.decisions[photo.id]
        let evaluation = model.scene(of: photo).flatMap { model.evaluations[$0.id]?.evaluations[photo.id] }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FaceOverlayImage(photo: photo, image: preview, faces: evaluation?.faces ?? [])
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text(photo.baseName).font(.headline).textSelection(.enabled)
                    Text(photo.files.map { $0.pathExtension.uppercased() }.joined(separator: " + ")
                         + " · " + photo.captureDate.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let size = photo.analysis?.pixelSize {
                        Text("\(Int(size.width)) × \(Int(size.height)) px · \(photo.category.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Entscheidung", selection: Binding<Int>(
                    get: { decision?.isManual == true ? (decision?.keep == true ? 1 : 2) : 0 },
                    set: { value in
                        withAnimation(decisionAnimation) {
                            model.setOverride(value == 0 ? nil : value == 1, for: photo)
                        }
                    }
                )) {
                    Text("Auto").tag(0)
                    Text("Behalten").tag(1)
                    Text("Aussortieren").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let decision {
                    HStack(alignment: .top) {
                        Image(systemName: decision.keep ? "checkmark.circle.fill" : "xmark.bin.fill")
                            .foregroundStyle(decision.keep ? Theme.keep : Theme.reject)
                        VStack(alignment: .leading) {
                            Text(decision.keep ? "Wird behalten" : "Wird aussortiert").font(.subheadline.bold())
                            Text(decision.reason).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if !decision.issues.isEmpty {
                        FlowIssues(issues: decision.issues)
                    }
                }

                if let evaluation {
                    GroupBox("Bewertung") {
                        VStack(spacing: 8) {
                            MetricRow(title: "Gesamt", value: evaluation.quality, symbol: "star")
                            MetricRow(title: "Schärfe", value: evaluation.sharpness, symbol: "scope")
                            if let face = evaluation.faceScore {
                                MetricRow(title: "Gesichter", value: face, symbol: "face.smiling")
                            }
                            MetricRow(title: "Belichtung", value: evaluation.exposure, symbol: "sun.max")
                            MetricRow(title: "Ästhetik", value: evaluation.aesthetics, symbol: "sparkles")
                        }
                        .padding(4)
                    }
                    if !evaluation.faces.isEmpty {
                        GroupBox("Personen") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(evaluation.faces.enumerated()), id: \.offset) { _, face in
                                    HStack {
                                        Text("Person \(face.trackID + 1)")
                                        Spacer()
                                        Label(face.eyesClosed ? "Augen zu" : "Augen offen",
                                              systemImage: face.eyesClosed ? "eye.slash.fill" : "eye.fill")
                                            .foregroundStyle(face.eyesClosed ? Theme.reject : Theme.keep)
                                        if face.lookingAway {
                                            Image(systemName: "person.fill.turn.left").foregroundStyle(.orange)
                                        }
                                        Text("\(Int(face.score * 100))")
                                            .monospacedDigit()
                                            .frame(width: 30, alignment: .trailing)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.callout)
                                }
                            }
                            .padding(4)
                        }
                    }
                }

                HStack {
                    if let scene = model.scene(of: photo), scene.photos.count > 1 {
                        Button("Szene vergleichen") { model.compareScene = scene }
                    }
                    Button("Im Finder zeigen") { model.revealInFinder(photo.primaryURL) }
                }
            }
            .padding()
        }
        .task(id: photo.id) {
            preview = await PreviewLoader.load(photo.primaryURL, maxPixel: 1600)
        }
    }
}

/// Bild mit eingezeichneten Gesichtern (grün = Augen offen, rot = Augen zu).
struct FaceOverlayImage: View {
    let photo: PhotoItem
    let image: CGImage?
    let faces: [FaceEvaluation]

    var body: some View {
        let aspect = photo.analysis.map { $0.pixelSize.width / max($0.pixelSize.height, 1) } ?? 1.5
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable()
            } else if let thumb = ThumbnailStore.image(for: photo) {
                Image(nsImage: thumb).resizable()
            } else {
                Rectangle().fill(.quaternary)
            }
            GeometryReader { geo in
                let boxes = photo.analysis?.faces ?? []
                ForEach(Array(boxes.enumerated()), id: \.offset) { index, face in
                    let rect = CGRect(x: face.boundingBox.minX * geo.size.width,
                                      y: (1 - face.boundingBox.maxY) * geo.size.height,
                                      width: face.boundingBox.width * geo.size.width,
                                      height: face.boundingBox.height * geo.size.height)
                    // Gesichtsbewertungen liegen in derselben Reihenfolge wie die erkannten Gesichter.
                    let closed = index < faces.count && faces[index].eyesClosed
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(closed ? Theme.reject : Theme.keep, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricRow: View {
    let title: String
    let value: Double
    let symbol: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .frame(width: 110, alignment: .leading)
            ProgressView(value: value)
                .tint(value > 0.66 ? Theme.keep : value > 0.4 ? .orange : Theme.reject)
            Text("\(Int(value * 100))")
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

private struct FlowIssues: View {
    let issues: Set<PhotoIssue>

    var body: some View {
        HStack {
            ForEach(PhotoIssue.allCases.filter(issues.contains), id: \.self) { issue in
                Label(issue.title, systemImage: issue.symbol)
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
        }
    }
}
