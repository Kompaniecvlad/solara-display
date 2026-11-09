import SwiftUI

struct DisplayCardView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(Int(display.percent.rounded()))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                stepButton("minus") { model.nudge(-BrightnessKey.step, for: display.id) }
                SolarSlider(value: percentBinding) {
                    model.setPercent(display.percent, for: display.id, hud: true)
                }
                .frame(height: 16)
                .accessibilityLabel(display.name)
                .accessibilityValue("\(Int(display.percent.rounded()))%")
                stepButton("plus") { model.nudge(BrightnessKey.step, for: display.id) }
            }
        }
        .padding(.vertical, 4)
    }

    private var percentBinding: Binding<Double> {
        Binding(
            get: { display.percent },
            set: { model.setPercent($0, for: display.id) }
        )
    }

    private var statusLine: String {
        let language = model.language
        if display.supportsXDR, let nits = display.estimatedNits {
            return language.localized("status.xdr \(nits)")
        }
        switch display.path {
        case .hardware: return language.localized("method.hardware")
        case .ddc: return language.localized("method.ddc")
        case .software: return language.localized("method.software")
        case .unavailable: return language.localized("method.unavailable")
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

struct SolarSlider: View {
    @Binding var value: Double
    var onCommit: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(value, 0), 100)
            let x = (clamped / 100) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(SolaraTheme.sunGradient)
                    .frame(width: max(x, 10))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .frame(width: 16, height: 16)
                    .offset(x: min(max(x - 8, 0), width - 16))
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = min(max((gesture.location.x / width) * 100.0, 0), 100)
                    }
                    .onEnded { _ in
                        onCommit?()
                    }
            )
        }
    }
}
