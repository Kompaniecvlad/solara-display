import AppKit

/// Maps the Mac brightness keys onto Solara’s 0…100 scale (up to 1600 nits).
enum BrightnessKey {
    case up
    case down

    static let step: Double = 6.25

    static func from(_ event: NSEvent) -> BrightnessKey? {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return nil }
        let keyCode = Int32((event.data1 & 0xFFFF0000) >> 16)
        let keyState = (event.data1 & 0x0000FF00) >> 8
        // 0x0A = keyDown / repeat. NX_KEYTYPE_BRIGHTNESS_UP = 2, DOWN = 3
        // (1 is volume down — do not treat it as brightness.)
        guard keyState == 0x0A else { return nil }
        switch keyCode {
        case 2: return .up
        case 3: return .down
        default: return nil
        }
    }
}

@MainActor
final class BrightnessKeyMonitor {
    private var local: Any?
    private var global: Any?
    var onKey: ((BrightnessKey) -> Void)?

    func start() {
        stop()
        local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            if let key = BrightnessKey.from(event) {
                self?.onKey?(key)
            }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            if let key = BrightnessKey.from(event) {
                self?.onKey?(key)
            }
        }
    }

    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        local = nil
        global = nil
    }
}
