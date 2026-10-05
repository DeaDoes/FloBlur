import AppKit
import SwiftUI

/// Brief floating bezel flashed on toggle, mirroring the original's
/// `ToggleHUD`: icon + state (+preset), fading out after a moment.
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
        guard let screen = NSScreen.main else { return }
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
                Image(systemName: enabled ? "circle.dashed" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(enabled ? .blue : .secondary)
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
