import AppKit
import Combine

/// Manages one `OverlayWindow` per display, mirroring the original's
/// `OverlayManager`: the overlay is parked directly beneath the anchor
/// window (the frontmost qualifying window) and sharp regions for the rest
/// of the pinned set are cut as holes (window-local coordinates).
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
    /// Last requested anchor per display, invalidated against the live stack.
    private var lastAnchor: [String: Int] = [:]
    private var refreshQueued = false
    /// Live Night Shift strength (0 off / 1 shifting), pushed by AppDelegate.
    /// The warm wash follows it — it must NOT be warm just because the
    /// toggle is on while Night Shift itself is off.
    var nightShiftStrength = 0.0

    // Peek: hovering a faded window brings it back while the cursor rests.
    private var mouseMonitors: [Any] = []
    private let peek = HoverPeek()
    private var lastPointerWindow: Int?

    init(settings: FloBlurSettings) {
        self.settings = settings
    }

    /// Applies a snapshot; returns the current pause state for menu display.
    @discardableResult
    func update(snapshot: DesktopSnapshot) -> PausedReason {
        // Our own Settings window in front: hold the current seating so the
        // effect stays put (and live) while it is adjusted.
        self.snapshot = snapshot
        // Click-through overlays are not desktop windows or hover targets.
        let ownNumbers = Set(windows.values.map(\.windowNumber))
        for (key, window) in windows {
            guard let requested = lastAnchor[key] else { continue }
            if !snapshot.overlayIsSeated(window.windowNumber, below: requested == -2 ? nil : requested,
                                         on: window.frame, overlayNumbers: ownNumbers) {
                lastAnchor[key] = nil
            }
        }
        self.snapshot.windows.removeAll { ownNumbers.contains($0.number) }
        let sharingPause = settings.disableWhileSharing && snapshot.captured
        if snapshot.activePID == ownPID, !sharingPause, lastPaused != .sharing { return lastPaused }
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

        if settings.disableWhileSharing, snapshot.captured {
            decide("paused-sharing")
            hideAll(animated: false)
            return .sharing
        }

        // Mission Control / App Exposé (gesture or keyboard): with Blur or
        // Both, dip out so every window shows sharp and identifiable.
        // Dim-only keeps dimming, as dim always does. Only the alpha fades —
        // seating, holes, and the converged blur stay parked, so the return
        // is a single fade-in instead of a full rebuild.
        if snapshot.missionControl, settings.style != .dim {
            peek.clear()
            decide("mc-sharp")
            for window in windows.values {
                window.fadeAlpha(to: 0, duration: 0.15)
            }
            return .none
        }

        if let name = snapshot.activeName,
           let bid = snapshot.activeBundleID,
           settings.excludedBundleIDs.contains(bid) {
            decide("paused-for-\(bid)")
            hideAll(animated: true)
            return .pausedForApp(name: name)
        }
        if settings.disableInFullScreen, snapshot.activeWindowInFullScreenSpace {
            decide("paused-fullscreen")
            hideAll(animated: true)
            return .fullScreen
        }

        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let style: FocusStyle = reduceTransparency ? .dim : settings.style

        let anchor = snapshot.activeWindow
        if anchor == nil, !settings.fadeDesktopWhenUnfocused {
            // No qualifying front window and the desktop should stay sharp:
            // stand down instead of full-covering (which blurred everything,
            // including the window in use, on transient states).
            decide("no-anchor-hide")
            hideAll(animated: true)
            return .none
        }
        var pinned = pinnedWindows(anchor: anchor)
        let hovered = snapshot.window(at: NSEvent.mouseLocation)
        lastPointerWindow = hovered?.number
        let candidate = hovered.flatMap { window in
            settings.peekEnabled && window.qualifiesForFocus && !pinned.contains(where: { $0.number == window.number })
                ? window.number : nil
        }
        peek.track(candidate, delay: settings.peekDelay) { [weak self] in
            self?.apply()
        }
        if let hovered, hovered.number == peek.revealedWindow {
            pinned.append(hovered)
        }

        let sharpNumbers = Set(pinned.map(\.number))
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
            let holes = snapshot.overlayCutouts(sharpWindows: sharpNumbers, anchor: anchor,
                                                workArea: screen.visibleFrame)
            let radius = style == .blur || style == .both
                ? settings.effectiveBlurRadius(forDisplay: key) : 0
            window.setHoles(holes, in: screen.frame)
            window.setBlur(radius: radius, animated: true)
            window.setDim(color: dimColor(for: key), animated: true)
            let opacity: Float = style == .dim || style == .both
                ? Float(settings.effectiveDimOpacity(forDisplay: key)) : 0
            window.setDim(opacity: opacity, animated: true)
            let requested = anchor?.number ?? -2
            if !window.isVisible || lastAnchor[key] != requested {
                if let anchor {
                    window.order(.below, relativeTo: anchor.number)
                } else {
                    window.orderFrontRegardless()
                }
                lastAnchor[key] = requested
            }
            window.fadeIn(animated: true)

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

    /// Windows that stay sharp: the anchor's siblings (unless faded too),
    /// tiled neighbors, and always-sharp apps. Peek is added after hit testing.
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
        let mine = snapshot.windows.filter { $0.pid == activePID && $0.qualifiesForFocus }
        var pinned = mine
        if settings.fadeOtherWindowsOfSameApp {
            pinned = mine.first.map { [$0] } ?? []
        }
        if let front = mine.first {
            pinned += tiledNeighbors(of: front, in: snapshot.windows)
        }
        pinned += sharpExtras(excluding: activePID)
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
            guard w.qualifiesForFocus, w.pid != front.pid else { return false }
            let a = front.rect, b = w.rect
            let sameHeight = abs(a.height - b.height) < 4 && abs(a.minY - b.minY) < 4
            let adjacent = abs(a.minX - b.maxX) < 4 || abs(b.minX - a.maxX) < 4
            let fills = abs(a.width + b.width - screenWidth) < 12
            return sameHeight && adjacent && fills
        }
    }

    private func screenHoldsSharpWindow(_ screen: NSScreen, anchor: WindowInfo?, pinned: [WindowInfo]) -> Bool {
        if let anchor, anchor.rect.intersects(screen.frame) { return true }
        return pinned.contains { $0.rect.intersects(screen.frame) }
    }

    // MARK: - Peek

    private func startMouseTracking() {
        stopMouseTracking()
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.cursorMoved() },
            NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.cursorMoved()
                return event
            },
        ].compactMap { $0 }
    }

    private func stopMouseTracking() {
        for monitor in mouseMonitors { NSEvent.removeMonitor(monitor) }
        mouseMonitors.removeAll()
        lastPointerWindow = nil
        peek.clear()
    }

    private func cursorMoved() {
        guard enabled, settings.peekEnabled else { return }
        let underPointer = snapshot.window(at: NSEvent.mouseLocation)?.number
        guard underPointer != lastPointerWindow else { return }
        lastPointerWindow = underPointer
        requestApply()
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
        peek.clear()
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
        // "Warm it up with Night Shift" follows the live strength: warm
        // only while the display is actually shifting, back afterwards.
        if settings.warmWithNightShift, nightShiftStrength > 0 {
            tint = .warm
        }
        switch tint {
        case .neutral: return .black
        case .warm: return NSColor(red: 0.13, green: 0.06, blue: 0.02, alpha: 1)
        case .custom: return .black
        }
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
