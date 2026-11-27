import AppKit

/// Tracks the desktop using window metadata only
/// (`CGWindowListCopyWindowInfo`). No Accessibility / Screen Recording
/// permission needed — same posture as the original app.
///
/// Cadence mirrors the original's `FocusTracker.updateCadence`: the poll
/// interval follows `min(time since last resolve, time since last input)` —
/// 0.1s when fresh, 2s while settling, 6s when idle (20% timer tolerance).
/// App switches, window closes, wakeups, and Space changes refresh
/// immediately via workspace notifications. Window order and geometry for the whole stack
/// determine which portions of pinned windows are visible.
final class ActiveWindowTracker {
    var onSnapshot: ((DesktopSnapshot) -> Void)?

    private var timer: Timer?
    private var stackTimer: Timer?
    private var lastWindowOrder: [Int] = []
    private var lastMC = false
    private var pollInterval = -1.0
    private var lastFullResolve = 0.0
    private var lastSnapshot = DesktopSnapshot.empty
    private var bundleIDCache: [pid_t: String] = [:]
    private var observers: [NSObjectProtocol] = []
    private let workspace = NSWorkspace.shared

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
                self?.refresh(force: name == NSWorkspace.didActivateApplicationNotification ||
                                         name == NSWorkspace.activeSpaceDidChangeNotification)
            })
        }
        updateCadence()
        refresh(force: true)
        // Space transitions and WindowServer restacking can happen while the
        // main poll is idle. Share the fast Mission Control scan with both.
        lastWindowOrder = []
        lastMC = false
        let watcher = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkWindowStack()
        }
        RunLoop.main.add(watcher, forMode: .common)
        stackTimer = watcher
    }

    deinit {
        stop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stackTimer?.invalidate()
        stackTimer = nil
        pollInterval = -1
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
        observers = []
    }

    /// External nudge (e.g. overlay needs fresh geometry now).
    func refresh(force: Bool) {
        poll(force: force)
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
        let now = CACurrentMediaTime()
        let heartbeatDue = now - lastHeartbeat > 1
        if heartbeatDue { lastHeartbeat = now }
        poll(force: heartbeatDue)
        updateCadence()
    }

    private var lastHeartbeat = 0.0

    private static func secondsSinceLastInput() -> Double {
        var best = Double.greatestFiniteMagnitude
        for type: CGEventType in [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel, .flagsChanged] {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if seconds < best {
                best = seconds
            }
        }
        return best
    }

    // MARK: - Snapshot

    private static func onScreenWindows() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    }

    private func checkWindowStack() {
        guard let list = Self.onScreenWindows() else { return }
        let mc = list.contains(where: Self.isMissionControlWindow)
        let captured = Self.sharingDetected(in: list)
        var order: [Int] = []
        var activeFrame: CGRect?
        for info in list {
            guard Self.number(info[kCGWindowLayer as String]) == 0,
                  let alpha = Self.number(info[kCGWindowAlpha as String]), alpha > 0,
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            order.append(number)
            if activeFrame == nil, let pid = lastSnapshot.activePID,
               Self.number(info[kCGWindowOwnerPID as String]) == CGFloat(pid),
               let bounds = Self.windowBounds(info), bounds.width >= 120, bounds.height >= 80 {
                activeFrame = Self.cocoaRect(fromCGBounds: bounds)
            }
        }
        let previousFrame = lastSnapshot.activeWindow?.rect
        let dragStarted = pollInterval > 0.1 &&
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDragged) < 0.25
        guard mc != lastMC || captured != lastSnapshot.captured || order != lastWindowOrder ||
              activeFrame != previousFrame || dragStarted else { return }
        lastMC = mc
        lastWindowOrder = order
        poll(list: list, captured: captured)
        updateCadence()
    }

    private func poll(force: Bool = false, list: [[String: Any]]? = nil, captured: Bool? = nil) {
        guard let list = list ?? Self.onScreenWindows() else { return }
        var snapshot = takeSnapshot(ownPID: NSRunningApplication.current.processIdentifier, list: list)
        snapshot.captured = captured ?? Self.sharingDetected(in: list)
        if snapshot != lastSnapshot {
            lastSnapshot = snapshot
            lastFullResolve = CACurrentMediaTime()
        } else if !force {
            return
        }
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

    private func takeSnapshot(ownPID: pid_t, list: [[String: Any]]) -> DesktopSnapshot {
        var snapshot = DesktopSnapshot()
        let frontmost = NSWorkspace.shared.frontmostApplication
        snapshot.activePID = frontmost?.processIdentifier
        snapshot.activeName = frontmost?.localizedName
        snapshot.activeBundleID = frontmost?.bundleIdentifier

        for info in list {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let layer = Self.number(info[kCGWindowLayer as String])
            let pid = Self.number(info[kCGWindowOwnerPID as String])
            if layer == 0 {
                if owner == "FloBlur" {
                    if let pid, pid_t(pid) != ownPID {
                        snapshot.floBlurOverlays += 1
                    }
                } else if owner == "defocus.me" {
                    snapshot.defocusOverlays += 1
                }
            }
            if Self.isMissionControlWindow(info) { snapshot.missionControl = true }
            guard Self.number(info[kCGWindowLayer as String]) == 0 else { continue }
            guard let alpha = Self.number(info[kCGWindowAlpha as String]), alpha > 0 else { continue }
            guard let pid = Self.number(info[kCGWindowOwnerPID as String]) else { continue }
            guard let windowNumber = Self.number(info[kCGWindowNumber as String]) else { continue }
            guard let bounds = Self.windowBounds(info) else { continue }
            let pidValue = pid_t(pid)
            snapshot.windows.append(WindowInfo(
                pid: pidValue,
                number: Int(windowNumber),
                owner: owner,
                bundleID: bundleID(for: pidValue, frontmost: frontmost),
                rect: Self.cocoaRect(fromCGBounds: bounds)
            ))
        }
        if let activeWindow = snapshot.activeWindow {
            snapshot.activeWindowInFullScreenSpace = SkyLight.isInFullScreenSpace(windowNumber: activeWindow.number)
        }
        return snapshot
    }

    private static func isMissionControlWindow(_ info: [String: Any]) -> Bool {
        guard info[kCGWindowOwnerName as String] as? String == "Dock" else { return false }
        let name = info[kCGWindowName as String] as? String ?? ""
        return name.contains("Mission Control") || name.contains("Exposé") || name.contains("Expose")
            || isFullScreenDockWindow(info)
    }

    /// A Dock-owned window covering (nearly) a whole screen.
    private static func isFullScreenDockWindow(_ info: [String: Any]) -> Bool {
        guard let b = info[kCGWindowBounds as String] as? [String: Any],
              let w = number(b["Width"]),
              let h = number(b["Height"])
        else { return false }
        let screens = NSScreen.screens
        return screens.contains { w >= $0.frame.width * 0.8 && h >= $0.frame.height * 0.8 }
    }

    private static func sharingDetected(in list: [[String: Any]]) -> Bool {
        displayMirroringEnabled() || list.contains { info in
            guard let title = info[kCGWindowName as String] as? String,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let alpha = number(info[kCGWindowAlpha as String]), alpha > 0 else { return false }
            return SharingWindow.matches(owner: owner, title: title)
        }
    }

    private static func displayMirroringEnabled() -> Bool {
        // Online displays include mirrored outputs, which NSScreen may coalesce.
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
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

    private static func windowBounds(_ info: [String: Any]) -> CGRect? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = number(bounds["X"]), let y = number(bounds["Y"]),
              let width = number(bounds["Width"]), let height = number(bounds["Height"]),
              width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func number(_ value: Any?) -> CGFloat? {
        if let d = value as? Double { return CGFloat(d) }
        if let i = value as? Int { return CGFloat(i) }
        if let f = value as? CGFloat { return f }
        return nil
    }
}
