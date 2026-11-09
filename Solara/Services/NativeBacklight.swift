import CoreGraphics
import Foundation
import IOKit

/// Hardware backlight for Apple panels: DisplayServices first, then IODisplay.
struct NativeBacklight {
    let displayID: CGDirectDisplayID

    static func isAvailable(for displayID: CGDirectDisplayID) -> Bool {
        if let get = DisplayServicesAPI.getBrightness {
            var value: Float = -1
            if get(displayID, &value) == 0, value >= 0 { return true }
        }
        return ioDisplayService(for: displayID) != 0
    }

    func read() -> Double? {
        if let get = DisplayServicesAPI.getBrightness {
            var value: Float = 0
            if get(displayID, &value) == 0 {
                return Double(min(max(value, 0), 1))
            }
        }
        return ioRead()
    }

    @discardableResult
    func write(_ value: Double) -> Bool {
        let clamped = Float(min(max(value, 0), 1))
        if let set = DisplayServicesAPI.setBrightness, set(displayID, clamped) == 0 {
            DisplayServicesAPI.notify?(displayID, Double(clamped))
            return true
        }
        return ioWrite(Double(clamped))
    }

    private func ioRead() -> Double? {
        let service = NativeBacklight.ioDisplayService(for: displayID)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var value: Float = 0
        let status = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
        guard status == KERN_SUCCESS else { return nil }
        return Double(min(max(value, 0), 1))
    }

    @discardableResult
    private func ioWrite(_ value: Double) -> Bool {
        let service = NativeBacklight.ioDisplayService(for: displayID)
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let status = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, Float(value))
        return status == KERN_SUCCESS
    }

    static func ioDisplayService(for displayID: CGDirectDisplayID) -> io_service_t {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            let info = IODisplayCreateInfoDictionary(service, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
            let serviceVendor = (info[kDisplayVendorID] as? NSNumber)?.uint32Value
            let serviceModel = (info[kDisplayProductID] as? NSNumber)?.uint32Value
            let serviceSerial = (info[kDisplaySerialNumber] as? NSNumber)?.uint32Value
            if serviceVendor == vendor, serviceModel == model, serial == 0 || serviceSerial == nil || serviceSerial == serial {
                return service
            }
            if CGDisplayIsBuiltin(displayID) != 0, (info["DisplayIsBuiltin"] as? Bool) == true || serviceVendor == vendor {
                return service
            }
            IOObjectRelease(service)
        }
        return 0
    }
}
