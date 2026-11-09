import AppKit
import SwiftUI

/// Brief on-screen readout so brightness keys show Solara’s scale, not the SDR cap.
@MainActor
final class BrightnessHUD {
    static let shared = BrightnessHUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(percent: Double, nits: Int?, on displayID: CGDirectDisplayID) {
        let screen = NSScreen.screens.first(where: { $0.solaraDisplayID == displayID }) ?? NSScreen.main
        guard let screen else { return }

        let root = BrightnessHUDView(
            percent: Int(percent.rounded()),
            nits: nits,
            language: AppModel.shared.language
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: 228, height: 96))

        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        self.panel = panel

        let frame = screen.visibleFrame
        let size = hosting.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 96
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 228, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct BrightnessHUDView: View {
    let percent: Int
    let nits: Int?
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(SolaraTheme.sunGradient)
                Text("Solara Display")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text("\(percent)%")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let nits {
                Text(language.localized("hud.nits \(nits)"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(width: 228)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
    }
}
