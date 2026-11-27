import AppKit

// From the repository root:
// swiftc FloBlur/Engine/FocusState.swift Tests/OverlayRegression.swift -o /tmp/floblur-overlay-check && /tmp/floblur-overlay-check
@main
struct OverlayRegression {
    static func main() {
        checkWindowStack()
        checkOverlayOrder()
        checkMaximizedWindow()
        checkHoverTransitions()
        checkSharingWindowTitles()
        print("Overlay geometry, hover, and sharing-title checks passed.")
    }

    static func checkWindowStack() {
        var desktop = DesktopSnapshot()
        func window(_ number: Int, _ rect: CGRect) -> WindowInfo {
            WindowInfo(pid: 1, number: number, owner: "Test", bundleID: nil, rect: rect)
        }
        desktop.windows = [
            window(1, CGRect(x: 10, y: 3, width: 8, height: 6)),
            window(2, CGRect(x: -8, y: 0, width: 24, height: 12)),
            window(3, CGRect(x: 4, y: -4, width: 24, height: 16)),
        ]

        // At any point precisely one hole is allowed if the top window is sharp,
        // including with two pinned windows and an unpinned panel above them.
        func verify() {
            for pinned: Set<Int> in [[], [2], [3], [2, 3], [1, 2, 3]] {
                let holes = desktop.visibleSharpRects(windowNumbers: pinned)
                for x in -10...30 {
                    for y in -6...18 {
                        let point = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                        let front = desktop.windows.first { $0.rect.contains(point) }
                        let expected = front.map { pinned.contains($0.number) } ?? false
                        precondition(holes.filter { $0.contains(point) }.count == (expected ? 1 : 0))
                        precondition(desktop.window(at: point)?.number == front?.number)
                    }
                }
            }
        }

        verify()
        desktop.windows[1].rect.origin.x += 5
        verify()
        desktop.windows.swapAt(0, 2)
        verify()
        desktop.windows[1].rect = desktop.windows[0].rect
        verify()
    }

    static func checkOverlayOrder() {
        let display = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        let other = display.offsetBy(dx: display.width, dy: 0)
        func window(_ number: Int, _ rect: CGRect) -> WindowInfo {
            WindowInfo(pid: 1, number: number, owner: "Test", bundleID: nil, rect: rect)
        }
        let chat = window(1, CGRect(x: 347, y: 115, width: 1130, height: 749))
        let overlay = window(2, display)
        let background = window(3, CGRect(x: 292, y: 183, width: 998, height: 683))
        let otherOverlay = window(4, other)
        func seated(_ windows: [WindowInfo], below anchor: Int? = 1) -> Bool {
            DesktopSnapshot(windows: windows).overlayIsSeated(2, below: anchor, on: display, overlayNumbers: [2, 4])
        }
        precondition(!seated([chat, background]))
        precondition(!seated([chat, background, overlay]))
        precondition(!seated([overlay, chat, background]))
        precondition(seated([chat, otherOverlay, window(5, other), overlay, background]))
        precondition(seated([overlay, background], below: nil))
        precondition(!seated([background, overlay], below: nil))
    }

    static func checkMaximizedWindow() {
        let workArea = CGRect(x: -1710, y: 64, width: 1710, height: 1010)
        var active = WindowInfo(pid: 1, number: 1, owner: "Test", bundleID: nil, rect: workArea)
        precondition(active.fillsWorkArea(workArea))
        active.rect = workArea.insetBy(dx: 8, dy: 8)
        precondition(active.fillsWorkArea(workArea))
        let background = WindowInfo(pid: 2, number: 2, owner: "Background", bundleID: nil, rect: workArea)
        let desktop = DesktopSnapshot(windows: [active, background])
        let cutouts = desktop.overlayCutouts(sharpWindows: [active.number], anchor: active, workArea: workArea)
        precondition(cutouts.contains { $0.contains(CGPoint(x: workArea.midX, y: workArea.midY)) })
        let exposedBackground = CGPoint(x: workArea.minX + 4, y: workArea.midY)
        precondition(!cutouts.contains { $0.contains(exposedBackground) })
        let pinnedCutouts = desktop.overlayCutouts(sharpWindows: [active.number, background.number],
                                                  anchor: active, workArea: workArea)
        precondition(pinnedCutouts.contains { $0.contains(exposedBackground) })
        precondition(!active.fillsWorkArea(workArea.offsetBy(dx: 1710, dy: 0)))
        active.rect = CGRect(x: -1710, y: 64, width: 855, height: 1010)
        precondition(!active.fillsWorkArea(workArea))
    }

    static func checkSharingWindowTitles() {
        precondition(SharingWindow.matches(owner: "zoom.us", title: "Sharing Toolbar"))
        precondition(SharingWindow.matches(owner: "Google Chrome", title: "Google Chrome is sharing your screen."))
        precondition(SharingWindow.matches(owner: "Microsoft Teams", title: "You’re sharing your screen"))
        precondition(!SharingWindow.matches(owner: "Google Chrome", title: "How to stop sharing your screen"))
        precondition(!SharingWindow.matches(owner: "TextEdit", title: "Stop sharing"))
        precondition(!SharingWindow.matches(owner: "zoom.us", title: ""))
    }

    static func checkHoverTransitions() {
        let peek = HoverPeek()
        var reveals: [Int] = []
        func hover(_ number: Int?) {
            peek.track(number, delay: 0.08) {
                if let number { reveals.append(number) }
            }
        }
        func wait(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }

        hover(2)
        wait(0.01)
        precondition(peek.revealedWindow == nil, "Revealed before the dwell elapsed")
        hover(3)
        wait(0.12)
        precondition(reveals == [3] && peek.revealedWindow == 3)
        hover(nil) // Pointer moved onto a pinned window or the desktop.
        precondition(peek.revealedWindow == nil)
        hover(2)
        peek.clear() // Disabled mid-hover.
        wait(0.12)
        precondition(reveals == [3] && peek.revealedWindow == nil)
    }
}
