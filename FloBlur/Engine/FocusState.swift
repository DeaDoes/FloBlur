import AppKit

/// One on-screen standard window, in Cocoa global coordinates.
/// `number` is the window-server window number, used to order the overlay
/// directly beneath a window (`order(_:relativeTo:)` works across processes).
struct WindowInfo: Equatable {
    var pid: pid_t
    var number: Int
    var owner: String
    var bundleID: String?
    var rect: NSRect

    var qualifiesForFocus: Bool { rect.width >= 120 && rect.height >= 80 }

    func fillsWorkArea(_ visibleFrame: CGRect) -> Bool {
        // macOS Fill can leave a small tiling margin at each edge.
        rect.contains(visibleFrame.insetBy(dx: 8, dy: 8))
    }
}

/// Why the effect is currently suppressed.
enum PausedReason: Equatable {
    case none
    case fullScreen
    case sharing
    case pausedForApp(name: String)

    var menuSubtitle: String? {
        switch self {
        case .none: return nil
        case .fullScreen: return "Paused in full screen"
        case .sharing: return "Paused while sharing"
        case let .pausedForApp(name): return "Paused for \(name)"
        }
    }
}

/// A point-in-time picture of the desktop, published for both the overlay
/// engine and the menu UI.
struct DesktopSnapshot: Equatable {
    var activePID: pid_t?
    var activeBundleID: String?
    var activeName: String?
    /// All on-screen layer-0 windows (frontmost first), Cocoa coordinates.
    var windows: [WindowInfo] = []
    /// Mission Control / Exposé / Launchpad is showing.
    var missionControl = false
    /// macOS reports mirroring or exposes a recognized sharing control.
    var captured = false
    var activeWindowInFullScreenSpace = false
    /// FloBlur-owned layer-0 windows (includes our own overlay).
    var floBlurOverlays = 0
    /// defocus.me-owned layer-0 windows (the paid app stacking underneath).
    var defocusOverlays = 0

    static let empty = DesktopSnapshot()
}

extension DesktopSnapshot {
    var activeWindow: WindowInfo? {
        guard let activePID else { return nil }
        return windows.first { $0.pid == activePID && $0.qualifiesForFocus }
    }

    func window(at point: CGPoint) -> WindowInfo? {
        windows.first { $0.rect.contains(point) }
    }

    /// Check the order macOS actually reports. Other displays have their own
    /// overlays and may share the same anchor.
    func overlayIsSeated(_ overlay: Int, below anchor: Int?, on display: CGRect, overlayNumbers: Set<Int>) -> Bool {
        var reachedAnchor = anchor == nil
        for window in windows {
            if window.number == overlay { return reachedAnchor }
            if window.number == anchor {
                reachedAnchor = true
            } else if reachedAnchor && !overlayNumbers.contains(window.number) && window.rect.intersects(display) {
                return false
            }
        }
        return false
    }

    func overlayCutouts(sharpWindows: Set<Int>, anchor: WindowInfo?, workArea: CGRect) -> [CGRect] {
        var cutouts = sharpWindows
        // The anchor normally sits above the overlay. Also mask its visible
        // area when maximized so blur and dim cannot bleed into it.
        if let anchor, !anchor.fillsWorkArea(workArea) {
            cutouts.remove(anchor.number)
        }
        return visibleSharpRects(windowNumbers: cutouts)
    }

    /// Visible pieces of sharp windows in global Cocoa coordinates. Every
    /// nearer layer-zero window occludes windows behind it, including small
    /// panels that cannot themselves become the focus anchor.
    func visibleSharpRects(windowNumbers: Set<Int>) -> [CGRect] {
        guard !windowNumbers.isEmpty else { return [] }
        var holes: [CGRect] = []
        for (index, window) in windows.enumerated() where windowNumbers.contains(window.number) {
            var pieces = [window.rect]
            for nearer in windows[..<index] {
                pieces = pieces.flatMap { $0.subtracting(nearer.rect) }
                if pieces.isEmpty { break }
            }
            holes.append(contentsOf: pieces)
        }
        return holes
    }
}

private extension CGRect {
    func subtracting(_ rect: CGRect) -> [CGRect] {
        let overlap = intersection(rect)
        guard !overlap.isEmpty else { return [self] }
        // Full-width strips above and below, then the two remaining sides.
        return [
            CGRect(x: minX, y: minY, width: width, height: overlap.minY - minY),
            CGRect(x: minX, y: overlap.maxY, width: width, height: maxY - overlap.maxY),
            CGRect(x: minX, y: overlap.minY, width: overlap.minX - minX, height: overlap.height),
            CGRect(x: overlap.maxX, y: overlap.minY, width: maxX - overlap.maxX, height: overlap.height),
        ].filter { !$0.isEmpty }
    }
}

/// Window titles are an optional fallback. Match known sharing controls
/// as complete titles so ordinary documents cannot trigger a pause.
enum SharingWindow {
    private static let owners: Set<String> = [
        "zoom.us", "zoom", "zoom workplace", "microsoft teams", "microsoft teams (work or school)",
        "webex", "google chrome", "google chrome canary", "microsoft edge", "chromium",
        "brave browser", "arc", "safari", "firefox", "opera", "slack", "discord", "facetime"
    ]
    private static let titles: Set<String> = [
        "stop sharing", "stop share", "sharing toolbar", "screen sharing toolbar",
        "sharing your screen", "sharing this screen", "you're sharing your screen",
        "you are sharing your screen"
    ]

    static func matches(owner: String, title: String) -> Bool {
        let owner = owner.lowercased()
        guard owners.contains(owner) else { return false }
        let title = title.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return titles.contains(title) || title == "\(owner) is sharing your screen"
    }
}

/// A reveal lasts only while the same visible, unpinned window is under the pointer.
final class HoverPeek {
    private var target: Int?
    private var timer: Timer?
    private(set) var revealedWindow: Int?

    func track(_ window: Int?, delay: TimeInterval, onReveal: @escaping () -> Void) {
        guard window != target else { return }
        clear()
        guard let window else { return }
        target = window
        let timer = Timer(timeInterval: max(0.05, delay), repeats: false) { [weak self] _ in
            guard let self, self.target == window else { return }
            self.timer = nil
            self.revealedWindow = window
            onReveal()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func clear() {
        timer?.invalidate()
        timer = nil
        target = nil
        revealedWindow = nil
    }
}

/// Observable holder so SwiftUI views (popover rows) can follow the desktop.
final class SnapshotStore: ObservableObject {
    @Published var snapshot = DesktopSnapshot.empty
    @Published var paused: PausedReason = .none
    /// Overlays owned by OTHER FloBlur processes (excluding ours).
    @Published var foreignFloBlurOverlays = 0
    /// Whether the paid app's overlay is also compositing.
    @Published var defocusRunning = false
}
