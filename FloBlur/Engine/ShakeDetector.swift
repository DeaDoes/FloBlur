import AppKit

/// Cursor-shake-to-toggle detector. Watches global mouse movement for rapid
/// back-and-forth motion: direction reversals past a minimum leg length
/// inside a short window. Higher sensitivity needs fewer reversals.
final class ShakeDetector {
    var onShake: (() -> Void)?

    private let sensitivity: () -> Double
    private var monitors: [Any] = []
    private var lastPoint = NSZeroPoint
    private var lastDirection = 0
    private var reversals = 0
    private var windowStart = Date.distantPast
    private var hasPoint = false
    private var lastFire = Date.distantPast

    /// - Parameter sensitivity: 0...1 from settings (`shakeSensitivity`).
    init(sensitivity: @escaping () -> Double) {
        self.sensitivity = sensitivity
    }

    func start() {
        stop()
        monitors = [
            // Note: drags excluded on purpose — dragging a window or slider
            // back and forth reverses constantly and must never toggle.
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.handleMovement(to: NSEvent.mouseLocation)
            },
        ].compactMap { $0 }
    }

    deinit {
        stop()
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        reset()
    }

    private func handleMovement(to point: NSPoint) {
        let now = Date()
        guard hasPoint else {
            lastPoint = point
            hasPoint = true
            return
        }
        let dx = point.x - lastPoint.x
        lastPoint = point
        // Narrow legs are curves and jitter, not shakes.
        guard abs(dx) >= 25 else { return }
        let direction = dx > 0 ? 1 : -1
        if now.timeIntervalSince(windowStart) > 0.9 {
            reversals = 0
            windowStart = now
            lastDirection = direction
            return
        }
        if direction != lastDirection {
            lastDirection = direction
            reversals += 1
            let needed = 4 + Int(((1 - min(max(sensitivity(), 0), 1)) * 4).rounded())
            guard reversals >= needed else { return }
            // Cooldown: one deliberate shake, one toggle — never strobe.
            guard now.timeIntervalSince(lastFire) > 1.0 else { return }
            lastFire = now
            reset()
            onShake?()
        }
    }

    private func reset() {
        reversals = 0
        lastDirection = 0
        hasPoint = false
        windowStart = .distantPast
    }
}
