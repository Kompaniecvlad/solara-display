import AppKit
import CoreGraphics
import Foundation

/// Owns the control stack for one connected screen.
@MainActor
final class DisplaySession {
    let id: CGDirectDisplayID
    let uuid: String
    var name: String
    let isBuiltin: Bool
    let isMain: Bool
    let supportsXDR: Bool
    let sdrNits: Int
    let peakNits: Int

    private let native: NativeBacklight?
    private var ddc: DDCController?
    private let software: SoftwareDimming
    private var xdr: XDROverlay?
    private(set) var path: ControlPath
    private(set) var percent: Double

    init(id: CGDirectDisplayID, ddcService: AnyObject?) {
        self.id = id
        self.uuid = id.solaraUUID
        self.isBuiltin = CGDisplayIsBuiltin(id) != 0
        self.isMain = CGMainDisplayID() == id
        self.supportsXDR = XDROverlay.isSupported(for: id)
        self.sdrNits = self.supportsXDR ? 600 : 400
        self.peakNits = self.supportsXDR ? 1600 : self.sdrNits
        self.name = Self.resolveName(for: id, builtin: isBuiltin)

        let nativeControl = NativeBacklight(displayID: id)
        self.native = NativeBacklight.isAvailable(for: id) ? nativeControl : nil
        if let ddcService {
            self.ddc = DDCController(displayID: id, service: ddcService)
        }
        self.software = SoftwareDimming(displayID: id)

        if native != nil {
            path = .hardware
        } else if ddc != nil {
            path = .ddc
        } else if software.isAvailable {
            path = .software
        } else {
            path = .unavailable
        }

        if let stored = UserDefaults.standard.object(forKey: Self.storageKey(uuid)) as? Double {
            percent = stored
        } else if let hardware = native?.read() {
            percent = Self.percent(fromHardware: hardware, supportsXDR: supportsXDR, sdrNits: sdrNits, peakNits: peakNits)
        } else if let ddc {
            percent = ddc.read() * 100
        } else {
            percent = 80
        }
    }

    var snapshot: DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            uuid: uuid,
            name: name,
            isBuiltin: isBuiltin,
            isMain: isMain,
            supportsXDR: supportsXDR,
            path: path,
            percent: percent,
            estimatedNits: supportsXDR ? Int((percent / 100 * Double(peakNits)).rounded()) : nil,
            sdrNits: sdrNits,
            peakNits: peakNits
        )
    }

    func apply(_ newPercent: Double, persist: Bool = true) {
        percent = min(max(newPercent, 0), 100)
        let hardwareFraction: Double
        let boostFraction: Double

        if supportsXDR, peakNits > sdrNits {
            let sdrShare = Double(sdrNits) / Double(peakNits)
            let p = percent / 100
            if p <= sdrShare {
                hardwareFraction = sdrShare == 0 ? 0 : p / sdrShare
                boostFraction = 0
            } else {
                hardwareFraction = 1
                boostFraction = (p - sdrShare) / (1 - sdrShare)
            }
        } else {
            hardwareFraction = percent / 100
            boostFraction = 0
        }

        var applied = false
        if let native {
            applied = native.write(hardwareFraction) || applied
        } else if let ddc, !ddc.degraded {
            ddc.write(hardwareFraction)
            applied = true
            if ddc.degraded {
                path = software.isAvailable ? .software : .unavailable
            }
        }

        if !applied, software.isAvailable {
            applied = software.write(hardwareFraction)
            if applied { path = .software }
        }

        if supportsXDR {
            if xdr == nil { xdr = XDROverlay(displayID: id) }
            xdr?.setBoost(boostFraction)
        }

        if persist {
            UserDefaults.standard.set(percent, forKey: Self.storageKey(uuid))
        }
    }

    func refreshName() {
        name = Self.resolveName(for: id, builtin: isBuiltin)
    }

    var sdrPercent: Double {
        guard peakNits > 0 else { return 100 }
        return Double(sdrNits) / Double(peakNits) * 100
    }

    func stop() {
        xdr?.tearDown()
    }

    private static func storageKey(_ uuid: String) -> String {
        "solara.brightness.\(uuid)"
    }

    private static func percent(fromHardware hardware: Double, supportsXDR: Bool, sdrNits: Int, peakNits: Int) -> Double {
        if supportsXDR, peakNits > 0 {
            return min(100, hardware * Double(sdrNits) / Double(peakNits) * 100)
        }
        return hardware * 100
    }

    private static func resolveName(for id: CGDirectDisplayID, builtin: Bool) -> String {
        if let screen = NSScreen.screens.first(where: { $0.solaraDisplayID == id }) {
            return screen.localizedName
        }
        let language = AppLanguage.current
        if builtin {
            return language.localized("display.builtin")
        }
        return language.localized("display.external")
    }
}
