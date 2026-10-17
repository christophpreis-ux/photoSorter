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
            CommandMenu("Foto") {
                Button("Behalten") { set(true) }
                    .keyboardShortcut("k", modifiers: [])
                Button("Aussortieren") { set(false) }
                    .keyboardShortcut("x", modifiers: [])
                Button("Automatisch entscheiden") { set(nil) }
                    .keyboardShortcut("a", modifiers: [])
                Divider()
                Button("Szene vergleichen") {
                    if let photo = model.selectedPhoto { model.compareScene = model.scene(of: photo) }
                }
                .keyboardShortcut("v", modifiers: [])
            }
        }
    }

    private func set(_ keep: Bool?) {
        guard model.phase == .review, let photo = model.selectedPhoto else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { model.setOverride(keep, for: photo) }
    }
}
