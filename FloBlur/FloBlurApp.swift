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
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}
