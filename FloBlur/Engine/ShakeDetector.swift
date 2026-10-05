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

    /// - Parameter sensitivity: 0...1 from settings (`shakeSensitivity`).
    init(sensitivity: @escaping () -> Double) {
        self.sensitivity = sensitivity
    }

    func start() {
        stop()
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
                self?.handleMovement(to: NSEvent.mouseLocation)
            },
        ].compactMap { $0 }
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
        guard abs(dx) >= 8 else { return } // ignore jitter
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
            let needed = 3 + Int(((1 - min(max(sensitivity(), 0), 1)) * 5).rounded())
            if reversals >= needed {
                reset()
                onShake?()
            }
        }
    }

    private func reset() {
        reversals = 0
        lastDirection = 0
        hasPoint = false
        windowStart = .distantPast
    }
}
