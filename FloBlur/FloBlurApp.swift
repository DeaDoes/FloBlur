import SwiftUI

@main
struct FloBlurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(delegate.settings)
                .environmentObject(delegate.snapshotStore)
                .environmentObject(delegate.scheduler)
                .environmentObject(delegate)
        } label: {
            MenuBarLabel(scheduler: delegate.scheduler)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu-bar label: icon alone when idle, icon + live mm:ss countdown while
/// a session runs (ticks via the scheduler's per-second heartbeat).
/// Click still opens the popover — Stop/Skip live one click away there.
private struct MenuBarLabel: View {
    @ObservedObject var scheduler: FocusScheduler

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: MenuBarIcon.image)
            if scheduler.phase != .idle {
                if scheduler.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(clockString)
                    .monospacedDigit()
            }
        }
    }

    private var clockString: String {
        let remaining = Int(scheduler.timeRemaining.rounded(.up))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
