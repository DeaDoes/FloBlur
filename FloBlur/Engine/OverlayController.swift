import AppKit
import Combine

/// Manages one `OverlayWindow` per display, mirroring the original's
/// `OverlayManager`: the overlay is parked directly beneath the anchor
/// window (the frontmost qualifying window) and sharp regions for the rest
/// of the pinned set are cut as holes (flipped window-local coords).
/// Show/hide fade the window alpha; intensities ramp in place.
final class OverlayController {
    private let settings: FloBlurSettings
    private var windows: [String: OverlayWindow] = [:]

    private var snapshot = DesktopSnapshot.empty
    private var enabled = false
    private var lastPaused: PausedReason = .none
    private let ownPID = NSRunningApplication.current.processIdentifier
    /// Last seating decision, for change-only diagnostics.
    private var lastDecision = ""
    /// Last anchor window number each overlay was seated below. Re-seating
    /// to the same anchor is skipped (matches the original's `lastAnchor`),
    /// except once a second (stale seatings self-heal).
    private var lastAnchor: [String: Int] = [:]
    private var lastSeatTime = 0.0
    private var refreshQueued = false

    // Peek: hovering a faded window brings it back while the cursor rests.
    private var mouseMonitors: [Any] = []
    private var hoverCandidate: Int? // window number
    private var peekNumber: Int?
    private var peekDeadline = Date.distantPast
    private var peekPump: Timer?

    init(settings: FloBlurSettings) {
        self.settings = settings
    }

    /// Applies a snapshot; returns the current pause state for menu display.
    @discardableResult
    func update(snapshot: DesktopSnapshot) -> PausedReason {
        // Our own Settings window in front: hold the current seating so the
        // effect stays put (and live) while it is adjusted.
        if snapshot.activePID == ownPID {
            self.snapshot = snapshot
            return lastPaused
        }
        self.snapshot = snapshot
        lastPaused = apply()
        return lastPaused
    }

    /// Coalesced re-apply for the settings path: a slider drag fires dozens
    /// of changes per second; they collapse into one apply per runloop.
    func requestApply() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshQueued = false
            _ = self?.apply()
        }
    }

    /// Space/display switches can re-stack windows behind our back — forget
    /// seated positions so the next apply re-seats unconditionally.
    func noteEnvironmentChanged() {
        lastAnchor = [:]
        apply()
    }

    @discardableResult
    func apply() -> PausedReason {
        let shouldEnable = settings.isEnabled
        if shouldEnable, !enabled {
            enabled = true
            startMouseTracking()
        } else if !shouldEnable, enabled {
            enabled = false
            stopMouseTracking()
        }
        guard enabled else {
            decide("off")
            hideAll(animated: true)
            return .none
        }

        // Never treat our own overlay windows as desktop windows.
        let ownNumbers = Set(windows.values.map { $0.windowNumber }.filter { $0 > 0 })
        if !ownNumbers.isEmpty {
            snapshot.windows.removeAll { ownNumbers.contains($0.number) }
        }

        // Mission Control / App Exposé (gesture or keyboard): with Blur or
        // Both, dip out so every window shows sharp and identifiable.
        // Dim-only keeps dimming, as dim always does. Only the alpha fades —
        // seating, holes, and the converged blur stay parked, so the return
        // is a single fade-in instead of a full rebuild.
        if snapshot.missionControl, settings.style != .dim {
            decide("mc-sharp")
            for window in windows.values {
                window.fadeAlpha(to: 0, duration: 0.15)
            }
            return .none
        }

        if settings.disableWhileSharing, snapshot.captured {
            decide("paused-sharing")
            hideAll(animated: true)
            return .sharing
        }
        if let name = snapshot.activeName,
           let bid = snapshot.activeBundleID,
           settings.excludedBundleIDs.contains(bid) {
            decide("paused-for-\(bid)")
            hideAll(animated: true)
            return .pausedForApp(name: name)
        }
        if settings.disableInFullScreen, isFullScreenActive() {
            decide("paused-fullscreen")
            hideAll(animated: true)
            return .fullScreen
        }

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let style: FocusStyle = reduceTransparency ? .dim : settings.style

        let anchor = anchorWindow()
        if anchor == nil, !settings.fadeDesktopWhenUnfocused {
            // No qualifying front window and the desktop should stay sharp:
            // stand down instead of full-covering (which blurred everything,
            // including the window in use, on transient states).
            decide("no-anchor-hide")
            hideAll(animated: true)
            return .none
        }
        let pinned = pinnedWindows(anchor: anchor)
        if let anchor {
            decide("seat-below-\(anchor.number)-holes-\(pinned.count)")
        } else {
            decide("no-anchor-desktop-cover-holes-\(pinned.count)")
        }

        pruneDetachedScreens()
        for screen in NSScreen.screens {
            let key = displayKey(for: screen)
            if settings.displayOverrides[key]?.neverFade == true {
                windows[key]?.fadeOut(animated: true)
                lastAnchor[key] = nil
                continue
            }
            if settings.fadeOnlyActiveDisplay, !screenHoldsSharpWindow(screen, anchor: anchor, pinned: pinned) {
                windows[key]?.fadeOut(animated: true)
                lastAnchor[key] = nil
                continue
            }
            let window = window(for: screen, key: key)
            window.fadeIn(animated: true)
            let now = CACurrentMediaTime()
            if let anchor {
                if lastAnchor[key] != anchor.number || now - lastSeatTime > 1.0 {
                    lastAnchor[key] = anchor.number
                    lastSeatTime = now
                    window.order(.below, relativeTo: anchor.number)
                }
            } else {
                if lastAnchor[key] != -2 || now - lastSeatTime > 1.0 {
                    lastAnchor[key] = -2
                    lastSeatTime = now
                    window.orderFrontRegardless()
                }
            }
            let radius = style == .blur || style == .both
                ? settings.effectiveBlurRadius(forDisplay: key) : 0
            window.setBlur(radius: radius, animated: true)
            window.setDim(color: dimColor(for: key), animated: true)
            let opacity: Float = style == .dim || style == .both
                ? Float(settings.effectiveDimOpacity(forDisplay: key)) : 0
            window.setDim(opacity: opacity, animated: true)
            window.setHoles(localHoles(pinned.filter { $0.number != anchor?.number }, on: window))
        }
        return .none
    }
    
    deinit {
        shutdown()
    }

    /// Full teardown for quit: never strand a visible overlay on screen.
    func shutdown() {
        enabled = false
        stopMouseTracking()
        for window in windows.values {
            window.setBlur(radius: 0, animated: false)
            window.setDim(opacity: 0, animated: false)
            window.fadeOut(animated: false)
        }
    }

    /// Visible overlays owned by this instance (for the stacking census).
    func visibleOverlayCount() -> Int {
        windows.values.filter { $0.isVisible }.count
    }

    // MARK: - Anchor + pinned set

    /// The anchor: first frontmost-app window at least 120×80, like the original.
    private func anchorWindow() -> WindowInfo? {
        guard let activePID = snapshot.activePID else { return nil }
        return snapshot.windows.first {
            $0.pid == activePID && $0.rect.width >= 120 && $0.rect.height >= 80
        }
    }

    /// Windows that stay sharp: the anchor's siblings (unless faded too),
    /// tiled neighbors, always-sharp apps, and the peek window.
    private func pinnedWindows(anchor: WindowInfo?) -> [WindowInfo] {
        guard let activePID = snapshot.activePID else {
            // Bare desktop: only fade when asked to; always-sharp apps and
            // peek still cut holes.
            if !settings.fadeDesktopWhenUnfocused { return [] }
            return sharpExtras(excluding: nil)
        }
        guard anchor != nil else {
            // Front app has no qualifying window: same desktop rule — fade it
            // (if asked) but keep always-sharp apps sharp.
            if !settings.fadeDesktopWhenUnfocused { return [] }
            return sharpExtras(excluding: activePID)
        }
        let mine = snapshot.windows.filter { $0.pid == activePID }
        var pinned = mine
        if settings.fadeOtherWindowsOfSameApp {
            pinned = mine.first.map { [$0] } ?? []
        }
        if let front = mine.first {
            pinned += tiledNeighbors(of: front, in: snapshot.windows)
        }
        pinned += sharpExtras(excluding: activePID)
        if let peek = peekNumber,
           let w = snapshot.windows.first(where: { $0.number == peek }),
           !pinned.contains(where: { $0.number == peek }) {
            pinned.append(w)
        }
        return pinned
    }

    private func sharpExtras(excluding pid: pid_t?) -> [WindowInfo] {
        snapshot.windows.filter { w in
            guard let bid = w.bundleID,
                  settings.alwaysSharpBundleIDs.contains(bid),
                  w.pid != pid
            else { return false }
            return true
        }
    }

    /// Other-app windows forming a Split View / tiled pair with the active
    /// window (same height, adjacent edge, widths filling the screen).
    private func tiledNeighbors(of front: WindowInfo, in windows: [WindowInfo]) -> [WindowInfo] {
        guard settings.keepTiledWindowsSharp,
              let screenWidth = NSScreen.screens.first(where: { $0.frame.intersects(front.rect) })?.frame.width
        else { return [] }
        return windows.filter { w in
            guard w.pid != front.pid else { return false }
            let a = front.rect, b = w.rect
            let sameHeight = abs(a.height - b.height) < 4 && abs(a.minY - b.minY) < 4
            let adjacent = abs(a.minX - b.maxX) < 4 || abs(b.minX - a.maxX) < 4
            let fills = abs(a.width + b.width - screenWidth) < 12
            return sameHeight && adjacent && fills
        }
    }

    /// Global Cocoa rects → flipped window-local hole rects.
    private func localHoles(_ globals: [WindowInfo], on window: NSWindow) -> [CGRect] {
        let frame = window.frame
        let height = frame.height
        return globals.compactMap { w -> CGRect? in
            guard w.rect.intersects(frame) else { return nil }
            let local = CGRect(
                x: w.rect.minX - frame.minX,
                y: height - (w.rect.maxY - frame.minY),
                width: w.rect.width,
                height: w.rect.height
            )
            let clipped = local.intersection(CGRect(origin: .zero, size: frame.size))
            return clipped.isEmpty ? nil : clipped
        }
    }

    private func isFullScreenActive() -> Bool {
        NSScreen.screens.contains { screen in
            frontmostRectOn(screen).map { coversScreen($0, screen.frame) } ?? false
        }
    }

    private func frontmostRectOn(_ screen: NSScreen) -> NSRect? {
        guard let pid = snapshot.activePID else { return nil }
        return snapshot.windows.first { $0.pid == pid && $0.rect.intersects(screen.frame) }?.rect
    }

    private func screenHoldsSharpWindow(_ screen: NSScreen, anchor: WindowInfo?, pinned: [WindowInfo]) -> Bool {
        if let anchor, anchor.rect.intersects(screen.frame) { return true }
        return pinned.contains { $0.rect.intersects(screen.frame) }
    }

    // MARK: - Peek

    private func startMouseTracking() {
        stopMouseTracking()
        mouseMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
                self?.cursorMoved()
            },
        ].compactMap { $0 }
    }

    private func stopMouseTracking() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors = []
        peekNumber = nil
        hoverCandidate = nil
        stopPeekPump()
    }

    private func cursorMoved() {
        let point = NSEvent.mouseLocation
        guard settings.peekEnabled, enabled else {
            peekNumber = nil
            hoverCandidate = nil
            return
        }
        let anchor = anchorWindow()
        let pinned = pinnedWindows(anchor: anchor)
        if let peek = peekNumber,
           let w = snapshot.windows.first(where: { $0.number == peek }),
           w.rect.contains(point) {
            return // stays back until the cursor leaves
        }
        peekNumber = nil
        if pinned.contains(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }) {
            hoverCandidate = nil
            return
        }
        guard let hovered = snapshot.windows.first(where: { $0.rect.contains(point) }) else {
            hoverCandidate = nil
            return
        }
        if hoverCandidate != hovered.number {
            hoverCandidate = hovered.number
            peekDeadline = Date().addingTimeInterval(max(0.05, settings.peekDelay))
            startPeekPump()
        }
    }

    private func startPeekPump() {
        stopPeekPump()
        // Common modes: mouse drags run the loop in event-tracking mode,
        // which would stall a default-mode timer and delay the reveal.
        let pump = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            self?.tickPeek()
        }
        RunLoop.main.add(pump, forMode: .common)
        peekPump = pump
    }

    private func stopPeekPump() {
        peekPump?.invalidate()
        peekPump = nil
    }

    private func tickPeek() {
        guard settings.peekEnabled, enabled,
              peekNumber == nil,
              hoverCandidate != nil,
              Date() >= peekDeadline
        else {
            // Anything other than "still waiting out the delay" stops the
            // pump — including peek being disabled mid-hover, which would
            // otherwise spin it forever.
            if !settings.peekEnabled || !enabled || peekNumber != nil || hoverCandidate == nil {
                stopPeekPump()
            }
            return
        }
        peekNumber = hoverCandidate
        stopPeekPump()
        apply()
    }

    // MARK: - Window management

    private func window(for screen: NSScreen, key: String) -> OverlayWindow {
        if let existing = windows[key] {
            if !existing.frame.equalTo(screen.frame) {
                existing.setFrame(screen.frame, display: true)
            }
            return existing
        }
        let window = OverlayWindow(frame: screen.frame)
        windows[key] = window
        return window
    }

    private func hideAll(animated: Bool) {
        for window in windows.values {
            window.setBlur(radius: 0, animated: animated)
            window.setDim(opacity: 0, animated: animated)
            window.fadeOut(animated: animated)
        }
        lastAnchor = [:]
    }

    private func pruneDetachedScreens() {
        let live = Set(NSScreen.screens.map { displayKey(for: $0) })
        for key in windows.keys where !live.contains(key) {
            windows[key]?.close()
            windows[key] = nil
        }
    }

    // MARK: - Helpers

    /// Change-only diagnostic: which seating decision is live.
    private func decide(_ decision: String) {
        guard decision != lastDecision else { return }
        lastDecision = decision
    }

    private func displayKey(for screen: NSScreen) -> String {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        return id.uuidString
    }

    private func dimColor(for key: String) -> NSColor {
        if settings.dimTint == .custom,
           let custom = NSColor(hexString: settings.dimTintCustom) {
            return custom
        }
        var tint = settings.dimTint
        if settings.warmWithNightShift {
            tint = .warm
        }
        switch tint {
        case .neutral: return .black
        case .warm: return NSColor(red: 0.13, green: 0.06, blue: 0.02, alpha: 1)
        case .custom: return .black
        }
    }

    private func coversScreen(_ rect: NSRect, _ frame: NSRect) -> Bool {
        abs(rect.minX - frame.minX) < 3
            && abs(rect.minY - frame.minY) < 3
            && abs(rect.width - frame.width) < 3
            && abs(rect.height - frame.height) < 3
    }
}

extension CGDirectDisplayID {
    var uuidString: String {
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(self)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, cfUUID) as String? ?? "display-\(self)"
        }
        return "display-\(self)"
    }
}
