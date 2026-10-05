import AppKit

/// Tracks the desktop using window metadata only
/// (`CGWindowListCopyWindowInfo`). No Accessibility / Screen Recording
/// permission needed — same posture as the original app.
///
/// Cadence mirrors the original's `FocusTracker.updateCadence`: the poll
/// interval follows `min(time since last resolve, time since last input)` —
/// 0.1s when fresh, 2s while settling, 6s when idle (20% timer tolerance).
/// App switches, window closes, wakeups, and Space changes refresh
/// immediately via workspace notifications. Only announcement-worthy layouts
/// propagate to the overlay; background flicker is cached silently.
final class ActiveWindowTracker {
    var onSnapshot: ((DesktopSnapshot) -> Void)?

    private var timer: Timer?
    private var pollInterval = -1.0
    private var lastFullResolve = 0.0
    private var lastSnapshot = DesktopSnapshot.empty
    private var lastEmittedKey = LayoutKey.empty
    private var bundleIDCache: [pid_t: String] = [:]
    private var observers: [NSObjectProtocol] = []
    private let workspace = NSWorkspace.shared
    private let ownPID = NSRunningApplication.current.processIdentifier

    func start() {
        stop()
        let center = workspace.notificationCenter
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] as [NSNotification.Name] {
            observers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if name == NSWorkspace.didTerminateApplicationNotification {
                    self?.forgetBundleID(from: notification)
                }
                self?.refresh(force: name == NSWorkspace.didActivateApplicationNotification)
            })
        }
        updateCadence()
        refresh(force: true)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pollInterval = -1
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
        observers = []
    }

    /// External nudge (e.g. overlay needs fresh geometry now).
    func refresh(force: Bool) {
        _ = force
        poll()
        updateCadence()
    }

    // MARK: - Cadence

    private func updateCadence() {
        let idle = min(CACurrentMediaTime() - lastFullResolve, Self.secondsSinceLastInput())
        let interval: Double
        if idle < 0.25 {
            interval = 0.1
        } else if idle < 0.5 {
            interval = 2.0
        } else {
            interval = 6.0
        }
        guard interval != pollInterval else { return }
        pollInterval = interval
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        poll()
        // Heartbeat: re-emit at most every second even when the layout key
        // is unchanged, so a stale seating can never stick — the overlay
        // re-asserts its position and the flash self-heals.
        if CACurrentMediaTime() - lastHeartbeat > 1.0 {
            lastHeartbeat = CACurrentMediaTime()
            lastEmittedKey = LayoutKey.empty
            poll()
        }
        updateCadence()
    }

    private var lastHeartbeat = 0.0

    private static func secondsSinceLastInput() -> Double {
        var best = Double.greatestFiniteMagnitude
        for type: CGEventType in [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .flagsChanged] {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if seconds < best {
                best = seconds
            }
        }
        return best
    }

    // MARK: - Snapshot

    private func poll() {
        let snapshot = takeSnapshot()
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        lastFullResolve = CACurrentMediaTime()
        let key = LayoutKey(of: snapshot)
        guard key != lastEmittedKey else { return }
        lastEmittedKey = key
        onSnapshot?(snapshot)
    }

    private func forgetBundleID(from notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        bundleIDCache[app.processIdentifier] = nil
    }

    private func bundleID(for pid: pid_t, frontmost: NSRunningApplication?) -> String? {
        if let cached = bundleIDCache[pid] { return cached }
        let bid: String?
        if frontmost?.processIdentifier == pid {
            bid = frontmost?.bundleIdentifier
        } else {
            bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }
        if let bid {
            bundleIDCache[pid] = bid
        }
        return bid
    }

    private func takeSnapshot() -> DesktopSnapshot {
        var snapshot = DesktopSnapshot()
        var dockNames: [String] = []
        let frontmost = NSWorkspace.shared.frontmostApplication
        snapshot.activePID = frontmost?.processIdentifier
        snapshot.activeName = frontmost?.localizedName
        snapshot.activeBundleID = frontmost?.bundleIdentifier

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return snapshot }

        for info in list {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let name = info[kCGWindowName as String] as? String ?? ""
            let layer = Self.number(info[kCGWindowLayer as String])
            if layer == 0 {
                if owner == "FloBlur" {
                    snapshot.floBlurOverlays += 1
                } else if owner == "defocus.me" {
                    snapshot.defocusOverlays += 1
                }
            }
            if owner == "Dock" {
                dockNames.append(name)
                if name.contains("Mission Control") || name.contains("Exposé") || name.contains("Expose") {
                    snapshot.missionControl = true
                } else if Self.isFullScreenDockWindow(info) {
                    snapshot.missionControl = true
                }
            }
            guard Self.number(info[kCGWindowLayer as String]) == 0 else { continue }
            guard let alpha = Self.number(info[kCGWindowAlpha as String]), alpha > 0 else { continue }
            guard let pid = Self.number(info[kCGWindowOwnerPID as String]) else { continue }
            guard let windowNumber = Self.number(info[kCGWindowNumber as String]) else { continue }
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = Self.number(b["X"]),
                  let y = Self.number(b["Y"]),
                  let w = Self.number(b["Width"]),
                  let h = Self.number(b["Height"]),
                  w >= 120, h >= 80
            else { continue }
            let pidValue = pid_t(pid)
            snapshot.windows.append(WindowInfo(
                pid: pidValue,
                number: Int(windowNumber),
                owner: owner,
                bundleID: bundleID(for: pidValue, frontmost: frontmost),
                rect: Self.cocoaRect(fromCGBounds: CGRect(x: x, y: y, width: w, height: h))
            ))
        }
        snapshot.captured = Self.anyDisplayCaptured()
        if snapshot.missionControl, !Self.mcLogged {
            Self.mcLogged = true
            print("[FloBlur] MC-signal, Dock windows: \(dockNames)")
        } else if !snapshot.missionControl {
            Self.mcLogged = false
        }
        return snapshot
    }

    private static var mcLogged = false

    /// A Dock-owned window covering (nearly) a whole screen.
    private static func isFullScreenDockWindow(_ info: [String: Any]) -> Bool {
        guard let b = info[kCGWindowBounds as String] as? [String: Any],
              let w = number(b["Width"]),
              let h = number(b["Height"])
        else { return false }
        let screens = NSScreen.screens
        return screens.contains { w >= $0.frame.width * 0.8 && h >= $0.frame.height * 0.8 }
    }

    /// Sharing/mirroring detection via the display mirror set.
    private static func anyDisplayCaptured() -> Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    /// CG window bounds use a top-left origin measured from the top of the
    /// main display; Cocoa uses bottom-left. Flip Y into Cocoa space.
    static func cocoaRect(fromCGBounds rect: CGRect) -> NSRect {
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(
            x: rect.minX,
            y: mainHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let d = value as? Double { return CGFloat(d) }
        if let i = value as? Int { return CGFloat(i) }
        if let f = value as? CGFloat { return f }
        return nil
    }
}
