import AppKit
import SwiftUI

/// Strips the default square MenuBarExtra chrome so only our rounded panel shows.
final class ClearWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    private func apply() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        round(window.contentView)
        round(window.contentView?.superview)

        guard let root = window.contentView?.superview else { return }
        root.layer?.backgroundColor = NSColor.clear.cgColor
        for subview in root.subviews {
            let name = String(describing: type(of: subview))
            if name.contains("Titlebar") || name.contains("Toolbar") || name.contains("Button") {
                subview.isHidden = true
            }
            if let effect = subview as? NSVisualEffectView {
                effect.material = .popover
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.wantsLayer = true
                effect.layer?.cornerRadius = 18
                effect.layer?.cornerCurve = .continuous
                effect.layer?.masksToBounds = true
            }
        }
    }

    private func round(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

struct ClearMenuWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> ClearWindowView {
        ClearWindowView()
    }

    func updateNSView(_ nsView: ClearWindowView, context: Context) {}
}
