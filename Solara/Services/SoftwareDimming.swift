import CoreGraphics
import Foundation

/// Darkens pixels via the display gamma table when hardware control is unavailable.
final class SoftwareDimming {
    let displayID: CGDirectDisplayID
    private let original: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])?
    private static let floor: CGGammaValue = 0.12

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
        CGDisplayRestoreColorSyncSettings()
        let capacity: UInt32 = 256
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        let status = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &sampleCount)
        if status == .success, sampleCount > 0 {
            let count = Int(sampleCount)
            original = (Array(red.prefix(count)), Array(green.prefix(count)), Array(blue.prefix(count)))
        } else {
            original = nil
        }
    }

    var isAvailable: Bool { original != nil }

    @discardableResult
    func write(_ value: Double) -> Bool {
        guard let original else { return false }
        let clamped = min(max(value, 0), 1)
        let factor = Self.floor + (1 - Self.floor) * CGGammaValue(clamped)
        var red = original.red.map { $0 * factor }
        var green = original.green.map { $0 * factor }
        var blue = original.blue.map { $0 * factor }
        return CGSetDisplayTransferByTable(displayID, UInt32(red.count), &red, &green, &blue) == .success
    }

    func restore() {
        CGDisplayRestoreColorSyncSettings()
    }
}
