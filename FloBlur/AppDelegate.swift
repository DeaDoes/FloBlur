import AppKit
import Combine
import SwiftUI

/// Wires the tracker to the overlay and menu state, and owns the
/// long-lived services (hotkey, scheduler).
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let settings = FloBlurSettings.shared
    let snapshotStore = SnapshotStore()
    let overlay: OverlayController
    let tracker = ActiveWindowTracker()
    let hotKey = HotKeyManager()
    let scheduler: FocusScheduler
    let nightShift = NightShiftMonitor()
    let hud = ToggleHUD()
    private lazy var shakeDetector = ShakeDetector(sensitivity: { [weak self] in
        self?.settings.shakeSensitivity ?? 0.5
    })

    private var cancellables = Set<AnyCancellable>()
    private var lastAutoPresetPID: pid_t?

    override init() {
        overlay = OverlayController(settings: settings)
        scheduler = FocusScheduler(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        retireDuplicateInstances()
        tracker.onSnapshot = { [weak self] snapshot in
            guard let self else { return }
            self.snapshotStore.snapshot = snapshot
            let paused = self.overlay.update(snapshot: snapshot)
            self.snapshotStore.paused = paused
            // Stacking census: other FloBlur copies / the paid app compositing
            // on top of us turn the background black — say so on screen.
            self.snapshotStore.foreignFloBlurOverlays = snapshot.floBlurOverlays
            self.snapshotStore.defocusRunning = snapshot.defocusOverlays > 0
            self.applyAutoPreset(snapshot: snapshot)
        }

        shakeDetector.onShake = { [weak self] in
            DispatchQueue.main.async {
                self?.settings.isEnabled.toggle()
            }
        }
        syncShakeDetector()
        // Note: no explicit syncAllHotKeys() here — the $ sinks below fire
        // immediately on subscribe and cover the initial registration.
        nightShift.onChange = { [weak self] _ in
            self?.overlay.requestApply()
        }
        nightShift.sync(enabled: settings.warmWithNightShift)

        // Any setting change re-applies the effect immediately — no need to
        // switch apps first. objectWillChange fires before the mutation, and
        // requestApply coalesces bursts (slider drags) per runloop.
        settings.objectWillChange.sink { [weak self] _ in
            self?.overlay.requestApply()
            DispatchQueue.main.async { [weak self] in self?.refreshOverlay() }
        }.store(in: &cancellables)
        settings.$shortcutEnabled.sink { [weak self] _ in self?.syncAllHotKeys() }
            .store(in: &cancellables)
        settings.$shortcutKeyCode.sink { [weak self] _ in self?.syncAllHotKeys() }
            .store(in: &cancellables)
        settings.$shortcutModifiers.sink { [weak self] _ in self?.syncAllHotKeys() }
            .store(in: &cancellables)
        settings.$presetHotKeys.sink { [weak self] _ in self?.syncAllHotKeys() }
            .store(in: &cancellables)
        settings.$customPresets.sink { [weak self] _ in self?.syncAllHotKeys() }
            .store(in: &cancellables)
        // @Published publishers emit in willSet (before mutation commits).
        // Hop to RunLoop.main so the sink executes post-didSet and the HUD
        // always receives the committed state matching the switch.
        settings.$isEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                let preset = self.settings.preset(id: self.settings.activePresetID)
                self.hud.flash(enabled: isEnabled, presetName: preset?.name)
            }
            .store(in: &cancellables)
        settings.$shakeEnabled.sink { [weak self] _ in self?.syncShakeDetector() }
            .store(in: &cancellables)
        settings.$warmWithNightShift.sink { [weak self] _ in
            guard let self else { return }
            self.nightShift.sync(enabled: self.settings.warmWithNightShift)
            self.overlay.requestApply()
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.overlay.noteEnvironmentChanged() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.overlay.noteEnvironmentChanged() }

        tracker.start()
        scheduler.start()
        refreshOverlay()

        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }

        if settings.checkUpdatesAutomatically {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                UpdateChecker.check()
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        tracker.stop()
        scheduler.stop()
        nightShift.stop()
        shakeDetector.stop()
        overlay.shutdown()
    }

    private var onboardingWindow: NSWindow?

    /// First-launch guide.
    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView()
                .environmentObject(settings)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 460, height: 380)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to FloBlur"
            window.contentView = hosting
            window.center()
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Single instance

    /// The plist ban doesn't cover debugger launches, so enforce it here:
    /// two copies mean two identical menu icons, popovers, and HUDs fighting
    /// over one switch — every "opposite" report so far fits that shape.
    /// Older copies quit gracefully (their own shutdown hides their overlay).
    private func retireDuplicateInstances() {
        let me = Bundle.main.bundleIdentifier
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == me && $0.processIdentifier != mine
        }
        guard !others.isEmpty else { return }
        for app in others {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.forceRetireSurvivors()
        }
    }

    private func forceRetireSurvivors() {
        let me = Bundle.main.bundleIdentifier
        let mine = ProcessInfo.processInfo.processIdentifier
        let survivors = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == me && $0.processIdentifier != mine
        }
        for app in survivors {
            kill(app.processIdentifier, SIGKILL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let stillThere = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == me && $0.processIdentifier != mine
            }
            if !stillThere.isEmpty {
                let alert = NSAlert()
                alert.messageText = "Another copy of FloBlur refused to quit."
                alert.informativeText = "Two copies fight over the same switch, so the effect and the readouts can disagree. Force-quit the other FloBlur in Activity Monitor."
                alert.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }

    // MARK: - URL schemes (floblur://toggle, on, off, preset/<id>,
    // pomodoro/start, pomodoro/skip, pomodoro/stop)

    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "floblur" else { return }
        // `floblur://toggle` puts the action in host, not path — accept both.
        var parts: [String] = []
        if let host = url.host, !host.isEmpty {
            parts.append(host)
        }
        parts += url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "toggle":
            settings.isEnabled.toggle()
        case "on":
            settings.isEnabled = true
        case "off":
            settings.isEnabled = false
        case "preset" where parts.count > 1:
            let id = parts[1...].joined(separator: "/")
            if let preset = settings.preset(id: id) ?? settings.allPresets.first(where: { $0.name.lowercased() == id.lowercased() }) {
                settings.applyPreset(preset)
                settings.isEnabled = true
            }
        case "pomodoro":
            switch parts.dropFirst().first {
            case "start": scheduler.startSession()
            case "skip": scheduler.skipPhase()
            case "stop": scheduler.stopSession()
            default: break
            }
        default:
            break
        }
    }

    private func syncShakeDetector() {
        if settings.shakeEnabled {
            shakeDetector.start()
        } else {
            shakeDetector.stop()
        }
    }

    private func refreshOverlay() {
        snapshotStore.paused = overlay.apply()
    }

    /// Main toggle + one hotkey per preset ("pressing it applies this preset
    /// and turns the effect on").
    private func syncAllHotKeys() {
        let main = HotKeyCombo(keyCode: settings.shortcutKeyCode, modifiers: settings.shortcutModifiers)
        var presets: [(id: Int, combo: HotKeyCombo, fire: () -> Void)] = []
        for (index, preset) in settings.allPresets.enumerated() {
            guard let combo = settings.presetHotKeys[preset.id] else { continue }
            presets.append((id: 1000 + index, combo: combo, fire: { [weak self] in
                guard let self, let preset = self.settings.preset(id: preset.id) else { return }
                self.settings.applyPreset(preset)
                self.settings.isEnabled = true
            }))
        }
        hotKey.sync(
            main: settings.shortcutEnabled ? (main, true) : nil,
            presets: presets,
            mainFire: { [weak self] in
                self?.settings.isEnabled.toggle()
            }
        )
    }

    /// "Bring an assigned app to the front and its preset is applied instantly."
    private func applyAutoPreset(snapshot: DesktopSnapshot) {
        guard let pid = snapshot.activePID,
              let bid = snapshot.activeBundleID,
              pid != lastAutoPresetPID
        else { return }
        lastAutoPresetPID = pid
        guard let presetID = settings.automaticPresetByBundleID[bid],
              let preset = settings.preset(id: presetID),
              settings.activePresetID != presetID
        else { return }
        settings.applyPreset(preset)
    }
}
