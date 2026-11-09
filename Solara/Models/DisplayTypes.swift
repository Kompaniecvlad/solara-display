import AppKit
import CoreGraphics
import Foundation

enum SolaraBrand {
    static let name = "Solara Display"
    static let websiteHost = "www.kompaniec.com"
    static let websiteURL = URL(string: "https://www.kompaniec.com")!
    static let bundleID = "com.kompaniec.Solara"
}

extension NSScreen {
    var solaraDisplayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

extension CGDirectDisplayID {
    var solaraUUID: String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(self)?.takeRetainedValue() else {
            return "display-\(self)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

enum ControlPath: String, Codable {
    case hardware
    case ddc
    case software
    case unavailable
}

struct DisplaySnapshot: Identifiable, Equatable {
    var id: CGDirectDisplayID
    var uuid: String
    var name: String
    var isBuiltin: Bool
    var isMain: Bool
    var supportsXDR: Bool
    var path: ControlPath
    var percent: Double
    var estimatedNits: Int?
    var sdrNits: Int
    var peakNits: Int
}
