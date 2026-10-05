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
    /// Some display is being captured (AirPlay mirroring / recording target).
    var captured = false
    /// FloBlur-owned layer-0 windows (includes our own overlay).
    var floBlurOverlays = 0
    /// defocus.me-owned layer-0 windows (the paid app stacking underneath).
    var defocusOverlays = 0

    static let empty = DesktopSnapshot()
}

/// Announcement-worthy layout: what actually re-seats the overlay.
/// Background flicker that doesn't touch these fields is cached silently.
struct LayoutKey: Equatable {
    var activePID: pid_t?
    var frontNumber: Int?
    var frontRect: String
    var windowCount: Int
    var missionControl: Bool
    var captured: Bool
    var floBlurOverlays: Int
    var defocusOverlays: Int

    static let empty = LayoutKey(activePID: nil, frontNumber: nil, frontRect: "", windowCount: 0, missionControl: false, captured: false, floBlurOverlays: 0, defocusOverlays: 0)

    init(activePID: pid_t?, frontNumber: Int?, frontRect: String, windowCount: Int, missionControl: Bool, captured: Bool, floBlurOverlays: Int = 0, defocusOverlays: Int = 0) {
        self.activePID = activePID
        self.frontNumber = frontNumber
        self.frontRect = frontRect
        self.windowCount = windowCount
        self.missionControl = missionControl
        self.captured = captured
        self.floBlurOverlays = floBlurOverlays
        self.defocusOverlays = defocusOverlays
    }

    init(of snapshot: DesktopSnapshot) {
        activePID = snapshot.activePID
        missionControl = snapshot.missionControl
        captured = snapshot.captured
        windowCount = snapshot.windows.count
        floBlurOverlays = snapshot.floBlurOverlays
        defocusOverlays = snapshot.defocusOverlays
        if let pid = snapshot.activePID,
           let front = snapshot.windows.first(where: { $0.pid == pid }) {
            frontNumber = front.number
            let r = front.rect
            frontRect = "\(r.origin.x):\(r.origin.y):\(r.size.width):\(r.size.height)"
        } else {
            frontNumber = nil
            frontRect = ""
        }
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
