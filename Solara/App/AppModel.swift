import AppKit
import CoreGraphics
import Foundation
import Combine
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var displays: [DisplaySnapshot] = []
    @Published var launchAtLogin = false
    @Published var showingAbout = false
    @Published var syncDisplays: Bool {
        didSet { UserDefaults.standard.set(syncDisplays, forKey: Self.syncKey) }
    }
    @Published var showMenuPercent: Bool {
        didSet { UserDefaults.standard.set(showMenuPercent, forKey: Self.menuPercentKey) }
    }
    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
            for session in sessions.values {
                session.refreshName()
            }
            publish()
        }
    }

    private var sessions: [CGDirectDisplayID: DisplaySession] = [:]
    private var previousPercents: [CGDirectDisplayID: Double] = [:]
    private var reconfiguration: NSObjectProtocol?
    private var poller: Timer?
    private let brightnessKeys = BrightnessKeyMonitor()

    private static let syncKey = "solara.syncDisplays"
    private static let menuPercentKey = "solara.showMenuPercent"

    var menuPercent: Int {
        let main = displays.first(where: \.isMain) ?? displays.first
        return Int((main?.percent ?? 0).rounded())
    }

    var isBoosting: Bool {
        displays.contains {
            $0.supportsXDR && $0.percent > (Double($0.sdrNits) / Double(max($0.peakNits, 1)) * 100) + 0.5
        }
    }

    var isAtPeak: Bool {
        displays.contains { $0.supportsXDR && $0.percent >= 97 }
    }

    var hasXDR: Bool {
        displays.contains { $0.supportsXDR }
    }

    var canRestore: Bool { !previousPercents.isEmpty }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.menuPercentKey) == nil {
            defaults.set(true, forKey: Self.menuPercentKey)
        }
        syncDisplays = defaults.bool(forKey: Self.syncKey)
        showMenuPercent = defaults.bool(forKey: Self.menuPercentKey)
        language = AppLanguage.current
    }

    func start() {
        refresh()
        applyStored()
        launchAtLogin = SMAppService.mainApp.status == .enabled

        reconfiguration = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        poller = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromHardware()
            }
        }
        if let poller {
            RunLoop.main.add(poller, forMode: .common)
        }

        brightnessKeys.onKey = { [weak self] key in
            self?.handleBrightnessKey(key)
        }
        brightnessKeys.start()
    }

    func refresh() {
        var online = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &online, &count)
        let ids = Array(online.prefix(Int(count)))
        let externals = ids.filter { CGDisplayIsBuiltin($0) == 0 }
        let ddcMap = DDCDiscovery.services(for: externals)

        let live = Set(ids)
        for stale in sessions.keys where !live.contains(stale) {
            sessions[stale]?.stop()
            sessions.removeValue(forKey: stale)
        }

        for id in ids {
            if sessions[id] == nil {
                let session = DisplaySession(id: id, ddcService: ddcMap[id])
                sessions[id] = session
                session.apply(session.percent, persist: false)
            } else {
                sessions[id]?.refreshName()
            }
        }

        publish()
    }

    func setPercent(_ percent: Double, for id: CGDirectDisplayID, hud: Bool = false) {
        apply(percent, targeting: id)
        publish()
        if hud { showHUD(for: id) }
    }

    func nudge(_ delta: Double, for id: CGDirectDisplayID) {
        guard let session = sessions[id] else { return }
        setPercent(session.percent + delta, for: id, hud: true)
    }

    func applyPreset(_ preset: BrightnessPreset) {
        if preset != .restore {
            previousPercents = Dictionary(uniqueKeysWithValues: sessions.map { ($0.key, $0.value.percent) })
        }
        for session in sessions.values {
            let value: Double
            if preset == .restore {
                value = previousPercents[session.id] ?? session.percent
            } else {
                value = preset.percent(for: session)
            }
            session.apply(value)
        }
        if preset == .restore {
            previousPercents.removeAll()
        }
        publish()
        if let focus = sessions.values.first(where: { $0.isBuiltin }) ?? sessions.values.first {
            showHUD(for: focus.id)
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func quit() {
        teardown()
        NSApp.terminate(nil)
    }

    func teardown() {
        brightnessKeys.stop()
        sessions.values.forEach { $0.stop() }
        BrightnessHUD.shared.hide()
    }

    private func handleBrightnessKey(_ key: BrightnessKey) {
        let session = sessions.values.first(where: { $0.isBuiltin })
            ?? sessions.values.first(where: { $0.isMain })
            ?? sessions.values.first
        guard let session else { return }
        let delta = key == .up ? BrightnessKey.step : -BrightnessKey.step
        apply(session.percent + delta, targeting: session.id)
        publish()
        showHUD(for: session.id)
        let id = session.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let again = self.sessions[id] else { return }
            again.apply(again.percent, persist: false)
        }
    }

    private func apply(_ percent: Double, targeting id: CGDirectDisplayID) {
        if syncDisplays {
            for session in sessions.values {
                session.apply(percent)
            }
        } else {
            sessions[id]?.apply(percent)
        }
    }

    private func showHUD(for id: CGDirectDisplayID) {
        guard let session = sessions[id] else { return }
        let nits = session.supportsXDR
            ? Int((session.percent / 100 * Double(session.peakNits)).rounded())
            : nil
        BrightnessHUD.shared.show(percent: session.percent, nits: nits, on: id)
    }

    func openWebsite() {
        NSWorkspace.shared.open(SolaraBrand.websiteURL)
    }

    private func applyStored() {
        for session in sessions.values {
            session.apply(session.percent, persist: false)
        }
        publish()
    }

    private func syncFromHardware() {
        for session in sessions.values where session.supportsXDR == false && session.path == .hardware {
            if let native = NativeBacklight(displayID: session.id).read() {
                let percent = native * 100
                if abs(percent - session.percent) > 1.5 {
                    session.apply(percent, persist: true)
                }
            }
        }
        publish()
    }

    private func publish() {
        displays = sessions.values
            .map(\.snapshot)
            .sorted { lhs, rhs in
                if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin }
                if lhs.isMain != rhs.isMain { return lhs.isMain }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
