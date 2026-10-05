import SwiftUI

@main
struct FloBlurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("FloBlur", systemImage: "circle.dashed") {
            MenuPopoverView()
                .environmentObject(delegate.settings)
                .environmentObject(delegate.snapshotStore)
                .environmentObject(delegate.scheduler)
                .environmentObject(delegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(delegate.settings)
                .environmentObject(delegate.snapshotStore)
                .environmentObject(delegate.scheduler)
        }
    }
}
