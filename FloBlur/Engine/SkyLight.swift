import AppKit

/// Dynamically loads WindowServer APIs for blur and native fullscreen Spaces.
enum SkyLight {
    // The handle stays loaded for the lifetime of the dynamically loaded functions.
    private static let framework = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_NOW
    )

    private static let connection: Int32? = {
        guard let framework, let symbol = dlsym(framework, "CGSMainConnectionID") else { return nil }
        typealias Connection = @convention(c) () -> Int32
        let id = unsafeBitCast(symbol, to: Connection.self)()
        return id == 0 ? nil : id
    }()

    private static let api: ((Int32, Int, Int32) -> Int32)? = {
        guard let framework else { return nil }
        for name in ["CGSSetWindowBackgroundBlurRadius", "SLSSetWindowBackgroundBlurRadius"] {
            if let sym = dlsym(framework, name) {
                typealias BlurFn = @convention(c) (Int32, Int, Int32) -> Int32
                let fn = unsafeBitCast(sym, to: BlurFn.self)
                return { c, w, r in fn(c, w, r) }
            }
        }
        return nil
    }()

    static var isAvailable: Bool { api != nil && connection != nil }

    @discardableResult
    static func setBackgroundBlurRadius(windowNumber: Int, radius: Int) -> Bool {
        guard let api, let connection else { return false }
        return api(connection, windowNumber, Int32(radius)) == 0
    }

    private typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    private static let spaceAPI: (copyWindowSpaces: CopyWindowSpaces, spaceType: SpaceType)? = {
        guard let framework,
              let copy = dlsym(framework, "SLSCopySpacesForWindows"),
              let type = dlsym(framework, "SLSSpaceGetType") else { return nil }
        return (unsafeBitCast(copy, to: CopyWindowSpaces.self), unsafeBitCast(type, to: SpaceType.self))
    }()

    /// The caller supplies an on-screen window. Native fullscreen and native
    /// Split View use dedicated Spaces, including on displays with a notch.
    static func isInFullScreenSpace(windowNumber: Int) -> Bool {
        guard let connection, let spaceAPI,
              let windowID = UInt32(exactly: windowNumber), windowID != 0 else { return false }
        let windows = [NSNumber(value: windowID)] as CFArray
        let allSpaces: Int32 = 0x7
        let fullScreenSpace: Int32 = 4
        guard let spaces = spaceAPI.copyWindowSpaces(connection, allSpaces, windows)?
            .takeRetainedValue() as? [NSNumber] else { return false }
        return spaces.contains { spaceAPI.spaceType(connection, $0.uint64Value) == fullScreenSpace }
    }

}
