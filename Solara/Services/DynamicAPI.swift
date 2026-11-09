import CoreGraphics
import Darwin
import Foundation
import IOKit

/// Resolves optional system symbols at runtime so Solara keeps working
/// when a framework moves into the dyld cache or a name disappears.
enum DynamicAPI {
    static let displayServices = load(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
    )

    static let coreDisplay = load(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay"
    )

    private static func load(_ paths: String...) -> UnsafeMutableRawPointer? {
        for path in paths {
            if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                return handle
            }
        }
        return nil
    }

    static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        let pointer = handle.flatMap { dlsym($0, name) } ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        guard let pointer else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

typealias DSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DSSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
typealias DSCanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
typealias DSBrightnessChanged = @convention(c) (CGDirectDisplayID, Double) -> Void
typealias CoreDisplayInfo = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
typealias AVCreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
typealias AVI2CRead = @convention(c) (UnsafeRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> kern_return_t
typealias AVI2CWrite = @convention(c) (UnsafeRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> kern_return_t

enum DisplayServicesAPI {
    static let getBrightness = DynamicAPI.symbol(DynamicAPI.displayServices, "DisplayServicesGetBrightness", as: DSGetBrightness.self)
    static let setBrightness = DynamicAPI.symbol(DynamicAPI.displayServices, "DisplayServicesSetBrightness", as: DSSetBrightness.self)
    static let canChange = DynamicAPI.symbol(DynamicAPI.displayServices, "DisplayServicesCanChangeBrightness", as: DSCanChangeBrightness.self)
    static let notify = DynamicAPI.symbol(DynamicAPI.displayServices, "DisplayServicesBrightnessChanged", as: DSBrightnessChanged.self)
}

enum CoreDisplayAPI {
    static let infoDictionary = DynamicAPI.symbol(DynamicAPI.coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary", as: CoreDisplayInfo.self)
}

enum AVServiceAPI {
    static let create = DynamicAPI.symbol(DynamicAPI.displayServices, "IOAVServiceCreateWithService", as: AVCreateWithService.self)
    static let read = DynamicAPI.symbol(DynamicAPI.displayServices, "IOAVServiceReadI2C", as: AVI2CRead.self)
    static let write = DynamicAPI.symbol(DynamicAPI.displayServices, "IOAVServiceWriteI2C", as: AVI2CWrite.self)

    static var isAvailable: Bool { create != nil && write != nil }
}
