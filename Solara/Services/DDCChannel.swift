import CoreGraphics
import Foundation
import IOKit

/// DDC/CI brightness over I²C on Apple Silicon (`DCPAVServiceProxy`).
final class DDCController {
    let displayID: CGDirectDisplayID
    private let service: AnyObject
    private let queue = DispatchQueue(label: "com.kompaniec.solara.ddc", qos: .userInitiated)
    private var maxValue: UInt16 = 100
    private var lastValue: Double = 1
    private var pending: Double?
    private var writing = false
    private var failures = 0
    private(set) var degraded = false

    static let luminance: UInt8 = 0x10

    init?(displayID: CGDirectDisplayID, service: AnyObject) {
        self.displayID = displayID
        self.service = service
        if let probe = DDCProtocol.read(service: service, vcp: Self.luminance) {
            maxValue = max(probe.max, 1)
            lastValue = Double(probe.current) / Double(maxValue)
        }
    }

    func read() -> Double { lastValue }

    func write(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        queue.async { [weak self] in
            guard let self, !self.degraded else { return }
            self.pending = clamped
            guard !self.writing else { return }
            self.writing = true
            self.drain()
        }
    }

    private func drain() {
        while true {
            guard let value = pending, !degraded else {
                writing = false
                return
            }
            pending = nil
            let raw = UInt16((value * Double(maxValue)).rounded())
            if DDCProtocol.write(service: service, vcp: Self.luminance, value: raw) {
                failures = 0
                lastValue = value
            } else {
                failures += 1
                if failures >= 4 {
                    degraded = true
                    writing = false
                    return
                }
            }
        }
    }
}

enum DDCProtocol {
    private static let chip: UInt32 = 0x37
    private static let register: UInt32 = 0x51

    static func write(service: AnyObject, vcp: UInt8, value: UInt16) -> Bool {
        guard let writeI2C = AVServiceAPI.write else { return false }
        var packet = wrap([vcp, UInt8(value >> 8), UInt8(value & 0xFF)])
        let opaque = Unmanaged.passUnretained(service).toOpaque()
        for attempt in 0..<3 {
            if attempt > 0 { usleep(20_000) }
            var ok = false
            for _ in 0..<2 {
                usleep(10_000)
                if writeI2C(opaque, chip, register, &packet, UInt32(packet.count)) == KERN_SUCCESS {
                    ok = true
                }
            }
            if ok { return true }
        }
        return false
    }

    static func read(service: AnyObject, vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C = AVServiceAPI.write, let readI2C = AVServiceAPI.read else { return nil }
        var request = wrap([vcp])
        let opaque = Unmanaged.passUnretained(service).toOpaque()
        for attempt in 0..<4 {
            if attempt > 0 { usleep(20_000) }
            usleep(10_000)
            guard writeI2C(opaque, chip, register, &request, UInt32(request.count)) == KERN_SUCCESS else { continue }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            guard readI2C(opaque, chip, 0, &reply, UInt32(reply.count)) == KERN_SUCCESS else { continue }
            guard reply[2] == 0x02, reply[4] == vcp else { continue }
            let maxValue = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            if maxValue > 0 { return (current, maxValue) }
        }
        return nil
    }

    /// VESA DDC/CI frame: `[0x80+|payload|+1, count] + payload + xor(0x6E, 0x51, …)`.
    private static func wrap(_ payload: [UInt8]) -> [UInt8] {
        var packet: [UInt8] = [UInt8(0x80 + payload.count + 1), UInt8(payload.count)] + payload + [0]
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in packet.dropLast() { checksum ^= byte }
        packet[packet.count - 1] = checksum
        return packet
    }
}

enum DDCDiscovery {
    static func services(for displayIDs: [CGDirectDisplayID]) -> [CGDirectDisplayID: AnyObject] {
        guard AVServiceAPI.isAvailable, let create = AVServiceAPI.create else { return [:] }
        let candidates = collectCandidates(create: create)
        guard !candidates.isEmpty else { return [:] }

        if displayIDs.count == 1, candidates.count == 1 {
            return [displayIDs[0]: candidates[0].service]
        }

        var scored: [(Int, CGDirectDisplayID, Int)] = []
        for id in displayIDs {
            for (index, candidate) in candidates.enumerated() {
                scored.append((score(displayID: id, candidate: candidate), id, index))
            }
        }

        var assigned: [CGDirectDisplayID: AnyObject] = [:]
        var used = Set<Int>()
        for entry in scored.sorted(by: { $0.0 > $1.0 }) where entry.0 >= 1 {
            guard assigned[entry.1] == nil, !used.contains(entry.2) else { continue }
            used.insert(entry.2)
            assigned[entry.1] = candidates[entry.2].service
        }
        return assigned
    }

    private struct Candidate {
        let service: AnyObject
        let productName: String
        let serial: UInt32
        let vendor: UInt32
        let product: UInt32
    }

    private static func collectCandidates(create: AVCreateWithService) -> [Candidate] {
        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var results: [Candidate] = []
        var lastVendor: UInt32 = 0
        var lastProduct: UInt32 = 0
        var lastSerial: UInt32 = 0
        var lastName = ""

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            var className = [CChar](repeating: 0, count: 128)
            IOObjectGetClass(entry, &className)
            let name = String(cString: className)

            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                if let attributes = property(entry, "DisplayAttributes") as? [String: Any],
                   let product = attributes["ProductAttributes"] as? [String: Any] {
                    lastVendor = (product["LegacyManufacturerID"] as? NSNumber)?.uint32Value ?? 0
                    lastProduct = (product["ProductID"] as? NSNumber)?.uint32Value ?? 0
                    lastSerial = (product["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
                    lastName = product["ProductName"] as? String ?? ""
                }
            } else if name == "DCPAVServiceProxy" {
                let location = property(entry, "Location") as? String
                guard location == nil || location == "External" else { continue }
                guard let unmanaged = create(kCFAllocatorDefault, entry) else { continue }
                let service = unmanaged.takeRetainedValue()
                results.append(Candidate(service: service, productName: lastName, serial: lastSerial, vendor: lastVendor, product: lastProduct))
            }
        }
        return results
    }

    private static func score(displayID: CGDirectDisplayID, candidate: Candidate) -> Int {
        var value = 0
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID) & 0xFFFF
        let serial = CGDisplaySerialNumber(displayID)
        if candidate.vendor != 0, candidate.vendor == vendor { value += 2 }
        if candidate.product != 0, candidate.product == model { value += 2 }
        if candidate.serial != 0, candidate.serial == serial { value += 3 }
        if let info = CoreDisplayAPI.infoDictionary?(displayID)?.takeRetainedValue() as? [String: Any],
           let names = info["DisplayProductName"] as? [String: String],
           !candidate.productName.isEmpty,
           names.values.contains(candidate.productName) {
            value += 2
        }
        return value
    }

    private static func property(_ entry: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
