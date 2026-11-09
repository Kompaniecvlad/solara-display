import AppKit
import CoreGraphics
import Metal
import QuartzCore

/// Full-screen EDR multiply overlay. Public Metal/AppKit only — this is the
/// path that still raises Liquid Retina XDR past the SDR software cap on macOS 27.
@MainActor
final class XDROverlay {
    let displayID: CGDirectDisplayID
    private var window: NSWindow?
    private var layer: CAMetalLayer?
    private var timer: Timer?
    private var factor: Double = 1
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var queue = device?.makeCommandQueue()

    /// ~1600 nits / ~600 nits SDR ceiling on mini-LED MacBook Pro panels.
    static let referenceHeadroom = 2.66

    static func isSupported(for displayID: CGDirectDisplayID) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.solaraDisplayID == displayID }) else { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.5
    }

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func setBoost(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        if clamped < 0.004 {
            tearDown()
            return
        }
        if window == nil { build() }
        apply(fraction: clamped)
    }

    func tearDown() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        layer = nil
        factor = 1
    }

    private func apply(fraction: Double) {
        guard let screen = NSScreen.screens.first(where: { $0.solaraDisplayID == displayID }) else { return }
        let live = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let ceiling = max(1.0, min(live, Self.referenceHeadroom))
        factor = 1.0 + fraction * (ceiling - 1.0)
        present()
    }

    private func build() {
        guard let screen = NSScreen.screens.first(where: { $0.solaraDisplayID == displayID }),
              let device else { return }

        let panel = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        var behavior: NSWindow.CollectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        if #available(macOS 15.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        panel.collectionBehavior = behavior
        panel.alphaValue = 0

        let metal = CAMetalLayer()
        metal.device = device
        metal.pixelFormat = .rgba16Float
        metal.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metal.wantsExtendedDynamicRangeContent = true
        metal.isOpaque = false
        metal.framebufferOnly = true
        metal.compositingFilter = "multiply"
        metal.presentsWithTransaction = false

        let host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer = metal
        metal.contentsScale = screen.backingScaleFactor
        metal.frame = host.bounds
        metal.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        metal.drawableSize = CGSize(
            width: max(2, screen.frame.width * screen.backingScaleFactor),
            height: max(2, screen.frame.height * screen.backingScaleFactor)
        )
        panel.contentView = host
        panel.orderFrontRegardless()

        window = panel
        layer = metal
        present()
        panel.alphaValue = 1

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.present()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func present() {
        guard let window, let layer, let queue else { return }
        if let screen = NSScreen.screens.first(where: { $0.solaraDisplayID == displayID }) {
            if window.frame != screen.frame {
                window.setFrame(screen.frame, display: true)
                layer.frame = CGRect(origin: .zero, size: screen.frame.size)
            }
            let pixels = CGSize(
                width: max(2, screen.frame.width * screen.backingScaleFactor),
                height: max(2, screen.frame.height * screen.backingScaleFactor)
            )
            if layer.drawableSize != pixels {
                layer.drawableSize = pixels
            }
        }
        guard let drawable = layer.nextDrawable() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let f = factor
        pass.colorAttachments[0].clearColor = MTLClearColor(red: f, green: f, blue: f, alpha: 1)
        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
