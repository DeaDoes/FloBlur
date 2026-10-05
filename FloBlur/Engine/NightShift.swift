import AppKit

/// Night Shift strength via the private `CBBlueLightClient`
/// (`getBlueLightStatus:` into a 128-byte status buffer). Mirrors the
/// original's `NightShift.strength()`: the call must succeed and two status
/// bytes must be set, otherwise the strength is 0.
enum NightShift {
    private static var client: NSObject? = {
        guard dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_NOW
        ) != nil,
            let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        return cls.init()
    }()

    private static let statusSelector = NSSelectorFromString("getBlueLightStatus:")

    /// 0 (off) or 1 (shifting). The original blends by a finer strength;
    /// the active flag is the part verified against its binary.
    static func strength() -> Double {
        guard let client else { return 0 }
        var status = [UInt8](repeating: 0, count: 128)
        typealias Fn = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
        guard let imp = client.method(for: statusSelector) else { return 0 }
        let fn = unsafeBitCast(imp, to: Fn.self)
        guard status.withUnsafeMutableBytes({ fn(client, statusSelector, $0.baseAddress!) }),
              status[0] != 0,
              status.count > 0x21,
              status[0x21] != 0
        else { return 0 }
        return 1
    }
}

/// Polls Night Shift strength while the warm-wash follow toggle is on.
final class NightShiftMonitor {
    private(set) var strength = 0.0
    var onChange: ((Double) -> Void)?

    private var timer: Timer?

    func sync(enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else {
            update(strength: 0)
            return
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        update(strength: NightShift.strength())
    }

    private func update(strength: Double) {
        guard strength != self.strength else { return }
        self.strength = strength
        onChange?(strength)
    }
}
