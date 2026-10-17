import SwiftUI

// MARK: - Sprüche

/// Sprüche im Stil der Filmreihe – eigene Formulierungen, nur kurze Anspielungen.
enum TerminatorQuotes {
    static let analysis = [
        "Zielerfassung aktiv. Unscharfe Fotos: identifiziert.",
        "Ich brauche deine Fotos, deine Ordner und deinen Speicherplatz.",
        "Skynet bleibt offline. Alles läuft auf deinem Mac.",
        "Scanne Gesichter … Mitleid: nicht installiert.",
        "Geschlossene Augen haben keine Zukunft.",
        "Er wird nicht aufhören. Niemals. Bis jedes Duplikat erledigt ist.",
        "Berechne Bedrohungsstufe für verwackelte Fotos …",
        "Kein Schicksal – außer dem, das wir selbst aussortieren.",
        "Modell 101. Spezialisiert auf Fotos.",
        "Lade Unschärfe-Detektor … online.",
        "Analysiere Ziele. Widerstand ist zwecklos.",
        "Ich suche Sarah Connor. Gefunden: 14 Fotos mit rotem Auge.",
    ]

    static let review = [
        "Zieh Fotos rüber – manuelle Befehle werden respektiert.",
        "Leertaste für Großansicht. Ich sehe alles.",
        "Ziele markiert. Warte auf Freigabe.",
        "Gnädig oder gnadenlos? Deine Entscheidung.",
    ]

    static let applied = [
        "Hasta la vista, Baby.",
        "Ich komme wieder. Mit dem nächsten Ordner.",
        "Mission erfüllt. Deine Festplatte dankt.",
        "Terminiert. Aber nur verschoben – ich bin ja kein Monster.",
        "Ziele neutralisiert. Keine Kollateralschäden an Favoriten.",
    ]

    static let welcome = [
        "Er fühlt kein Mitleid. Er kennt keine Reue. Er findet jedes verwackelte Foto.",
        "Aus der Zukunft geschickt, um deine Fotomediathek zu retten.",
        "Ich komme wieder. Und dann ist dein Ordner aufgeräumt.",
    ]

    static func random(_ list: [String]) -> String { list.randomElement() ?? "" }
}

/// Rang nach Anzahl der insgesamt terminierten Fotos.
enum TerminatorRank {
    static let levels: [(threshold: Int, title: String)] = [
        (0, "Rekrut"), (50, "T-600"), (250, "T-800"), (1000, "T-1000"), (5000, "T-X"), (20000, "Skynet"),
    ]

    static func title(for count: Int) -> String {
        levels.last { count >= $0.threshold }?.title ?? "Rekrut"
    }

    static func next(after count: Int) -> (title: String, remaining: Int)? {
        levels.first { $0.threshold > count }.map { ($0.title, $0.threshold - count) }
    }
}

enum HUD {
    static let red = Color(red: 1, green: 0.16, blue: 0.1)
    static let font = Font.system(.caption, design: .monospaced).weight(.semibold)
}

// MARK: - Feuer-Fortschrittsbalken

/// Fortschrittsbalken, der brennt: Flammenzungen, Funkenflug und eine glühende Spitze.
struct FlameProgressBar: View {
    var progress: Double
    var barHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let flameSpace = size.height - barHeight
                let bar = CGRect(x: 0, y: flameSpace, width: size.width, height: barHeight)
                let width = max(0, min(1, progress)) * size.width
                let filled = CGRect(x: 0, y: flameSpace, width: width, height: barHeight)

                context.fill(Path(roundedRect: bar, cornerRadius: barHeight / 2), with: .color(.white.opacity(0.08)))
                context.stroke(Path(roundedRect: bar, cornerRadius: barHeight / 2), with: .color(.white.opacity(0.1)), lineWidth: 1)
                guard width > 2 else { return }

                // Flammen über dem Balken
                var flames = context
                flames.addFilter(.blur(radius: 2.5))
                for x in stride(from: 4.0, to: width, by: 7) {
                    let n = (sin(x * 0.17 + t * 9.1) + sin(x * 0.071 - t * 5.3) + sin(x * 0.31 + t * 13.7) * 0.5 + 2.5) / 5
                    let ramp = 0.35 + 0.65 * (x / max(width, 1))
                    let height = (6 + n * (flameSpace - 4)) * ramp
                    var tongue = Path()
                    tongue.move(to: CGPoint(x: x - 6, y: flameSpace + 3))
                    tongue.addQuadCurve(to: CGPoint(x: x + sin(t * 7 + x) * 2, y: flameSpace - height),
                                        control: CGPoint(x: x - 5, y: flameSpace - height * 0.45))
                    tongue.addQuadCurve(to: CGPoint(x: x + 6, y: flameSpace + 3),
                                        control: CGPoint(x: x + 5, y: flameSpace - height * 0.45))
                    flames.fill(tongue, with: .linearGradient(
                        Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.5), .orange, Color.red.opacity(0)]),
                        startPoint: CGPoint(x: x, y: flameSpace + 2), endPoint: CGPoint(x: x, y: flameSpace - height)))
                }

                // Glühender Balken
                context.fill(Path(roundedRect: filled, cornerRadius: barHeight / 2), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.45, green: 0, blue: 0), .red, .orange, Color(red: 1, green: 0.9, blue: 0.4)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: width, y: 0)))

                // Funken
                for i in 0..<34 {
                    let seed = Double(i)
                    let phase = (t * (0.45 + seed.truncatingRemainder(dividingBy: 5) * 0.08) + seed * 0.137).truncatingRemainder(dividingBy: 1)
                    let x = (seed * 0.618_034).truncatingRemainder(dividingBy: 1) * width + sin(t * 3 + seed) * 6
                    let y = flameSpace - phase * (flameSpace + 10)
                    let r = 1.6 * (1 - phase) + 0.4
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                                 with: .color(Color(red: 1, green: 0.6 + 0.3 * (1 - phase), blue: 0.2).opacity(1 - phase)))
                }

                // Glühende Spitze
                let tip = CGPoint(x: width, y: flameSpace + barHeight / 2)
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 14, y: tip.y - 14, width: 28, height: 28)),
                             with: .radialGradient(Gradient(colors: [.white, .yellow.opacity(0.8), .orange.opacity(0)]),
                                                   center: tip, startRadius: 0, endRadius: 14))
            }
        }
        .frame(height: barHeight + 34)
        .accessibilityElement()
        .accessibilityLabel("Fortschritt")
        .accessibilityValue("\(Int(progress * 100)) Prozent")
    }
}

// MARK: - HUD-Scanner

/// Rot eingefärbte Zielerfassung des gerade analysierten Fotos.
struct HUDScanner: View {
    let image: NSImage?
    let lines: [String]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Bild füllt den Rahmen, ohne das Layout zu vergrößern.
                Color.black
                    .overlay {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .saturation(0)
                                .colorMultiply(Color(red: 1, green: 0.3, blue: 0.25))
                                .contrast(1.3)
                        }
                    }
                    .clipped()
                // Scanlinien
                Canvas { context, size in
                    for y in stride(from: 0, to: size.height, by: 3) {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.25)))
                    }
                    let sweep = (t * 0.6).truncatingRemainder(dividingBy: 1) * size.height
                    context.fill(Path(CGRect(x: 0, y: sweep - 18, width: size.width, height: 18)), with: .linearGradient(
                        Gradient(colors: [HUD.red.opacity(0), HUD.red.opacity(0.55)]),
                        startPoint: CGPoint(x: 0, y: sweep - 18), endPoint: CGPoint(x: 0, y: sweep)))
                    context.fill(Path(CGRect(x: 0, y: sweep, width: size.width, height: 1.5)), with: .color(HUD.red))
                }
                Reticle(rotation: t * 40)
                    .frame(width: 90, height: 90)
                    .offset(x: sin(t * 0.9) * 40, y: cos(t * 1.3) * 25)
                CornerBrackets().stroke(HUD.red, lineWidth: 2).padding(8)
                VStack(alignment: .leading, spacing: 2) {
                    if !lines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(HUD.font).foregroundStyle(HUD.red).lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    Text(Int(t * 2) % 2 == 0 ? "■ ANALYSE LÄUFT" : "□ ANALYSE LÄUFT")
                        .font(HUD.font).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(HUD.red.opacity(0.5)))
            .shadow(color: HUD.red.opacity(0.35), radius: 20)
        }
    }
}

struct Reticle: View {
    var rotation: Double

    var body: some View {
        ZStack {
            Circle().trim(from: 0.05, to: 0.2).stroke(HUD.red, lineWidth: 2)
            Circle().trim(from: 0.3, to: 0.45).stroke(HUD.red, lineWidth: 2)
            Circle().trim(from: 0.55, to: 0.7).stroke(HUD.red, lineWidth: 2)
            Circle().trim(from: 0.8, to: 0.95).stroke(HUD.red, lineWidth: 2)
            Circle().stroke(HUD.red.opacity(0.4), lineWidth: 1).padding(14)
            Path { p in
                p.move(to: CGPoint(x: 45, y: 0)); p.addLine(to: CGPoint(x: 45, y: 30))
                p.move(to: CGPoint(x: 45, y: 60)); p.addLine(to: CGPoint(x: 45, y: 90))
                p.move(to: CGPoint(x: 0, y: 45)); p.addLine(to: CGPoint(x: 30, y: 45))
                p.move(to: CGPoint(x: 60, y: 45)); p.addLine(to: CGPoint(x: 90, y: 45))
            }
            .stroke(HUD.red, lineWidth: 1.5)
        }
        .rotationEffect(.degrees(rotation))
    }
}

struct CornerBrackets: Shape {
    var length: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0), (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0), (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        return p
    }
}

// MARK: - Rotes Auge & Glitch-Titel

/// Pulsierendes rotes Roboterauge mit rotierender Zielerfassung.
struct RedEye: View {
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.85 + 0.15 * sin(t * 2.4)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [HUD.red.opacity(0.6 * pulse), .clear], center: .center,
                                         startRadius: 0, endRadius: size * 0.9))
                    .frame(width: size * 1.8, height: size * 1.8)
                Circle()
                    .strokeBorder(Color.gray.opacity(0.6), lineWidth: size * 0.05)
                    .background(Circle().fill(Color.black))
                    .frame(width: size, height: size)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.8), Color(red: 1, green: 0.4, blue: 0.2), .red,
                                                  Color(red: 0.4, green: 0, blue: 0)],
                                         center: UnitPoint(x: 0.42, y: 0.42), startRadius: 0, endRadius: size * 0.36))
                    .frame(width: size * 0.66 * pulse, height: size * 0.66 * pulse)
                    .shadow(color: .red, radius: 18 * pulse)
                Reticle(rotation: t * 25)
                    .frame(width: size * 1.45, height: size * 1.45)
                    .opacity(0.8)
            }
        }
        .frame(width: size * 1.8, height: size * 1.8)
    }
}

/// Titel mit gelegentlichem Glitch (rot/cyan versetzt).
struct GlitchText: View {
    let text: String
    var font: Font = .system(size: 40, weight: .black, design: .rounded)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 12.5)
            let glitch = tick % 37 < 3
            ZStack {
                Text(text).font(font).foregroundStyle(Color.cyan.opacity(glitch ? 0.8 : 0)).offset(x: glitch ? -3 : 0, y: glitch ? 1 : 0)
                Text(text).font(font).foregroundStyle(HUD.red.opacity(glitch ? 0.9 : 0)).offset(x: glitch ? 3 : 0, y: glitch ? -1 : 0)
                Text(text).font(font).foregroundStyle(.white)
                    .shadow(color: HUD.red.opacity(0.6), radius: 12)
                    .offset(x: glitch ? CGFloat(tick % 5 - 2) : 0)
            }
            .kerning(2)
        }
    }
}

/// Wechselnder Spruch mit Schreibmaschinen-Effekt.
struct QuoteTicker: View {
    let quotes: [String]
    var interval: TimeInterval = 5
    @State private var index = 0
    @State private var visible = 0

    var body: some View {
        let quote = quotes.isEmpty ? "" : quotes[index % quotes.count]
        Text("› " + String(quote.prefix(visible)) + (visible < quote.count ? "▌" : ""))
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(HUD.red)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .task(id: index) {
                visible = 0
                for step in 0...quote.count {
                    visible = step
                    try? await Task.sleep(for: .milliseconds(28))
                }
                try? await Task.sleep(for: .seconds(interval))
                index += 1
            }
            .onAppear { index = Int.random(in: 0..<max(quotes.count, 1)) }
    }
}

// MARK: - Schuss-Animation

/// Nach dem Terminieren: Fadenkreuz zieht zu, Mündungsblitz, Einschusslöcher, „TERMINIERT“.
struct TerminatedBurst: View {
    let count: Int
    @Binding var isPresented: Bool
    @State private var stage = 0
    @State private var shake: CGFloat = 0

    private let holes: [CGPoint] = [CGPoint(x: 0.32, y: 0.38), CGPoint(x: 0.66, y: 0.30), CGPoint(x: 0.55, y: 0.66)]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(stage >= 1 ? 0.75 : 0.0)

                if stage == 0 || stage == 1 {
                    Reticle(rotation: Double(stage) * 90)
                        .frame(width: stage == 0 ? 520 : 120, height: stage == 0 ? 520 : 120)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }

                if stage >= 2 {
                    Canvas { context, size in
                        for (index, hole) in holes.enumerated() where stage >= 2 + index {
                            let center = CGPoint(x: hole.x * size.width, y: hole.y * size.height)
                            for ray in 0..<9 {
                                let angle = Double(ray) / 9 * 2 * .pi + Double(index)
                                let length = 40 + Double((ray * 37 + index * 11) % 50)
                                var crack = Path()
                                crack.move(to: center)
                                crack.addLine(to: CGPoint(x: center.x + cos(angle) * length * 0.5 + 6, y: center.y + sin(angle) * length * 0.5))
                                crack.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
                                context.stroke(crack, with: .color(.white.opacity(0.65)), lineWidth: 1.2)
                            }
                            context.fill(Path(ellipseIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)),
                                         with: .radialGradient(Gradient(colors: [.black, Color(white: 0.15), .white.opacity(0.6)]),
                                                               center: center, startRadius: 0, endRadius: 11))
                        }
                    }
                }

                if stage >= 5 {
                    VStack(spacing: 10) {
                        GlitchText(text: "TERMINIERT", font: .system(size: 64, weight: .black, design: .rounded))
                        Text("\(count) Fotos neutralisiert")
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(HUD.red)
                    }
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                }

                // Mündungsblitz
                if stage == 2 || stage == 3 || stage == 4 {
                    Color.white.opacity(0.0).overlay(Color.white.opacity(flashOpacity))
                }
            }
            .offset(x: shake)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    @State private var flashOpacity = 0.0

    private func run() async {
        withAnimation(.easeIn(duration: 0.45)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(480))
        for shot in 2...4 {
            stage = shot
            flashOpacity = 0.85
            withAnimation(.easeOut(duration: 0.18)) { flashOpacity = 0 }
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 8)) { shake = shot % 2 == 0 ? 14 : -14 }
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) { shake = 0 }
            try? await Task.sleep(for: .milliseconds(170))
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { stage = 5 }
        try? await Task.sleep(for: .seconds(2.2))
        dismiss()
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.4)) { isPresented = false }
    }
}
