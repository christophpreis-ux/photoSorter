import SwiftUI

@main
struct PhotoSorterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 1050, minHeight: 680)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Ordner öffnen …") { model.chooseFolder() }
                    .keyboardShortcut("o")
            }
            // Tasten K / X / A / V werden direkt in der Übersicht verarbeitet (damit Textfelder nicht blockiert werden).
            CommandMenu("Foto") {
                Button("Behalten (K)") { set(true) }
                Button("Aussortieren (X)") { set(false) }
                Button("Automatisch entscheiden (A)") { set(nil) }
                Divider()
                Button("Szene vergleichen (V)") {
                    if let photo = model.selectedPhoto { model.compareScene = model.scene(of: photo) }
                }
            }
        }
    }

    private func set(_ keep: Bool?) {
        guard model.phase == .review, let photo = model.selectedPhoto else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { model.setOverride(keep, for: photo) }
    }
}
