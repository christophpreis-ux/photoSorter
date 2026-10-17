import SwiftUI

/// Dunkles Graphit-Farbschema – neutral, damit Fotos farblich nicht verfälscht wirken.
enum Theme {
    static let background = Color(red: 0.102, green: 0.106, blue: 0.118)
    static let surface = Color(red: 0.145, green: 0.152, blue: 0.167)
    static let surfaceRaised = Color(red: 0.19, green: 0.198, blue: 0.215)
    static let stroke = Color.white.opacity(0.07)

    static let accent = Color(red: 0.38, green: 0.63, blue: 1.0)
    static let keep = Color(red: 0.24, green: 0.82, blue: 0.45)
    static let reject = Color(red: 1.0, green: 0.38, blue: 0.35)
    static let keepArea = keep.opacity(0.08)
    static let rejectArea = reject.opacity(0.08)
}

extension View {
    /// Schwebendes Liquid-Glass-Panel.
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
