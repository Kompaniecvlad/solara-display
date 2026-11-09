import SwiftUI

enum SolaraTheme {
    static let gold = Color(red: 0.98, green: 0.72, blue: 0.22)
    static let amber = Color(red: 1.0, green: 0.54, blue: 0.18)
    static let dusk = Color(red: 0.10, green: 0.08, blue: 0.07)
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.93)

    static let sunGradient = LinearGradient(
        colors: [gold, amber],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension View {
    func solaraPanel() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(ClearMenuWindow())
            .solaraClearWindowBackground()
    }

    @ViewBuilder
    private func solaraClearWindowBackground() -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(.clear, for: .window)
        } else {
            self
        }
    }
}
