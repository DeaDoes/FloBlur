import AppKit
import SwiftUI

/// Brief floating bezel flashed on toggle, mirroring the original's
/// `ToggleHUD`: icon + state (+preset), fading out after a moment.
///
/// Takes explicit `enabled` state and preset name dispatched from the
/// post-mutation sink so what it shows always matches the master switch.
final class ToggleHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func flash(enabled: Bool, presetName: String?) {
        let content = HUDView(enabled: enabled, presetName: presetName)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 76)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = hosting
        } else {
            panel = NSPanel(
                contentRect: hosting.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            panel.contentView = hosting
            self.panel = panel
        }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { return }
        let origin = NSPoint(
            x: screen.frame.midX - 110,
            y: screen.frame.maxY - 220
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ _ in
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private struct HUDView: View {
        var enabled: Bool
        var presetName: String?

        var body: some View {
            HStack(spacing: 10) {
                if enabled {
                    Image(nsImage: MenuBarIcon.hudImage)
                        .renderingMode(.template)
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(enabled ? "Focus on" : "Focus off")
                        .font(.headline)
                    Text(enabled ? (presetName ?? "Background softened") : "Everything sharp")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 220, height: 76)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 12)
            )
        }
    }
}

// MARK: - MenuBarIcon

/// Vector template image matching the FloBlur logo:
/// outer 16-segment dashed circle, inner iris, and center pupil cutout.
enum MenuBarIcon {
    static func makeImage(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = size / 18.0
            let center = CGPoint(x: size / 2, y: size / 2)

            // Outer dashed circle (16 segments, matching the logo)
            ctx.saveGState()
            let ringPath = CGMutablePath()
            ringPath.addArc(center: center, radius: 7.2 * s, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.addPath(ringPath)
            ctx.setLineDash(phase: 0, lengths: [1.8 * s, 1.0 * s])
            ctx.setLineWidth(1.3 * s)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.strokePath()
            ctx.restoreGState()

            // Inner iris with cutout pupil
            ctx.saveGState()
            let rIris = 4.5 * s
            let rPupil = 1.6 * s
            ctx.addEllipse(in: CGRect(x: center.x - rIris, y: center.y - rIris, width: rIris * 2, height: rIris * 2))
            ctx.addEllipse(in: CGRect(x: center.x - rPupil, y: center.y - rPupil, width: rPupil * 2, height: rPupil * 2))
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()

            return true
        }
        img.isTemplate = true
        return img
    }

    static let image: NSImage = makeImage(size: 18)
    static let hudImage: NSImage = makeImage(size: 28)
}
