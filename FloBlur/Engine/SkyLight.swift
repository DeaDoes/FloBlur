import AppKit

/// Dynamic loader for the private SkyLight background-blur API the original
/// app uses (`CGSSetWindowBackgroundBlurRadius`, also exported as
/// `SLSSetWindowBackgroundBlurRadius`).
///
/// This is what lets the effect work with window metadata only — no Screen
/// Recording or Accessibility permission. Fails closed (`false` /
/// `isAvailable == false`) so callers fall back to dim-only.
enum SkyLight {
    private static let api: (connection: Int32, setBlur: (Int32, Int, Int32) -> Int32)? = {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_NOW
        ) else { return nil }
        defer { /* keep handle open for the life of the process */ }
        guard let symConn = dlsym(handle, "CGSMainConnectionID") else { return nil }
        typealias ConnFn = @convention(c) () -> Int32
        let connection = unsafeBitCast(symConn, to: ConnFn.self)()
        guard connection != 0 else { return nil }
        for name in ["CGSSetWindowBackgroundBlurRadius", "SLSSetWindowBackgroundBlurRadius"] {
            if let sym = dlsym(handle, name) {
                typealias BlurFn = @convention(c) (Int32, Int, Int32) -> Int32
                let fn = unsafeBitCast(sym, to: BlurFn.self)
                return (connection, { c, w, r in fn(c, w, r) })
            }
        }
        return nil
    }()

    static var isAvailable: Bool { api != nil }

    /// Applies a background-blur radius to a window. Returns true on success.
    @discardableResult
    static func setBackgroundBlurRadius(windowNumber: Int, radius: Int) -> Bool {
        guard let api = api else { return false }
        return api.setBlur(api.connection, windowNumber, Int32(radius)) == 0
    }
}
