import SwiftUI
import AppKit
import ServiceManagement

/// Settings window, replicating the original's sidebar layout:
/// General / Appearance / Displays / Timing / Apps.
struct SettingsView: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @EnvironmentObject private var store: SnapshotStore
    @EnvironmentObject private var scheduler: FocusScheduler

    @State private var selection = Pane.general

    enum Pane: Hashable {
        case general, appearance, displays, timing, apps, about
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gear").tag(Pane.general)
                Label("Appearance", systemImage: "slider.horizontal.3").tag(Pane.appearance)
                Label("Displays", systemImage: "display.2").tag(Pane.displays)
                Label("Timing", systemImage: "timer").tag(Pane.timing)
                Label("Apps", systemImage: "app.badge.checkmark").tag(Pane.apps)
                Label("About", systemImage: "info.circle").tag(Pane.about)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            ScrollView {
                switch selection {
                case .general: GeneralPane()
                case .appearance: AppearancePane()
                case .displays: DisplaysPane()
                case .timing: TimingPane()
                case .apps: AppsPane()
                case .about: AboutPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("FloBlur Settings")
        .frame(minWidth: 720, minHeight: 560)
        .environmentObject(settings)
        .environmentObject(store)
        .environmentObject(scheduler)
    }
}

// MARK: - Shared bits

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

private struct Row<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
        .padding(.vertical, 9)
    }
}

private struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.title3)
            .padding(.top, 14)
    }
}

private extension View {
    func panePadding() -> some View {
        padding(.horizontal, 22)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var settings: FloBlurSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 36))
                VStack(alignment: .leading) {
                    Text("FloBlur").font(.title2)
                    Text("Stay sharp. Defocus the rest.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            Card {
                LaunchAtLoginRow()
            }
            SectionTitle(text: "Updates")
            Card {
                Row(title: "Check for updates automatically") {
                    Toggle("", isOn: $settings.checkUpdatesAutomatically).labelsHidden()
                }
                Divider()
                Row(title: "Download and install updates automatically") {
                    Toggle("", isOn: $settings.downloadUpdatesAutomatically).labelsHidden()
                }
                Divider()
                Text("Downloaded updates are installed safely when FloBlur quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            SectionTitle(text: "Cursor shake")
            Card {
                Row(title: "Toggle by shaking the cursor") {
                    Toggle("", isOn: $settings.shakeEnabled).labelsHidden()
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text("Low").font(.caption).foregroundStyle(.blue)
                        Slider(value: $settings.shakeSensitivity, in: 0...1)
                            .frame(width: 200)
                        Text("High").font(.caption).foregroundStyle(.blue)
                    }
                    Text("Higher means less shaking is needed — and more accidental toggles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            SectionTitle(text: "Global shortcut")
            Card {
                Row(title: "Enable the shortcut") {
                    Toggle("", isOn: $settings.shortcutEnabled).labelsHidden()
                }
                Divider()
                HStack {
                    Text("Combination")
                    Spacer()
                    ShortcutRecorderView(
                        keyCode: $settings.shortcutKeyCode,
                        modifiers: $settings.shortcutModifiers
                    )
                    .frame(width: 220)
                }
                .padding(.vertical, 8)
            }
            SectionTitle(text: "Shortcuts & Focus")
            Text("Shortcuts can Open URL floblur://toggle, floblur://on, floblur://off, or floblur://preset/coding. Add a Focus Filter under System Settings → Focus → Work (or Study) so the effect turns on with that Focus.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .panePadding()
    }
}

private struct LaunchAtLoginRow: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading) {
            Row(title: "Launch FloBlur at login") {
                Toggle("", isOn: $launchAtLogin).labelsHidden()
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            errorMessage = nil
                        } catch {
                            errorMessage = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
        }
    }
}

// MARK: - Appearance

private struct AppearancePane: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @State private var showingPresetManager = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Presets")
            Card {
                HStack(spacing: 6) {
                    ForEach(settings.allPresets.prefix(8)) { preset in
                        PresetChip(
                            name: preset.name,
                            isActive: settings.activePresetID == preset.id
                        ) {
                            settings.applyPreset(preset)
                        }
                    }
                    Spacer()
                    Button("Manage…") { showingPresetManager = true }
                        .buttonStyle(.link)
                }
                .padding(.vertical, 10)
                Divider()
                Text("Apply a preset, then save to store this look, exclusions, and always-sharp apps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            PreviewCard()
            SectionTitle(text: "Style")
            Card {
                Row(title: "Effect") {
                    Picker("", selection: $settings.style) {
                        Text("Blur").tag(FocusStyle.blur)
                        Text("Dim").tag(FocusStyle.dim)
                        Text("Both").tag(FocusStyle.both)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                }
                Divider()
                IntensityRow(icon: "drop.fill", title: "Blur", value: $settings.blurIntensity)
                Divider()
                IntensityRow(icon: "circle.lefthalf.filled", title: "Dim", value: $settings.dimIntensity)
                Divider()
                Row(title: "Colour") {
                    Picker("", selection: $settings.dimTint) {
                        ForEach(DimTint.allCases, id: \.self) { tint in
                            Text(tint.displayName).tag(tint)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    if settings.dimTint == .custom {
                        ColorPicker("", selection: Binding(
                            get: { Color(hexString: settings.dimTintCustom) },
                            set: { settings.dimTintCustom = $0.toHexString() }
                        ))
                        .labelsHidden()
                    }
                }
                Divider()
                Row(title: "Warm it up with Night Shift") {
                    Toggle("", isOn: $settings.warmWithNightShift).labelsHidden()
                }
                Divider()
                Text("While Night Shift is shifting the display, the wash warms with it and goes back on its own afterwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            SectionTitle(text: "Behaviour")
            Card {
                BehaviourToggle(title: "Fade the active app's other windows too", value: $settings.fadeOtherWindowsOfSameApp)
                Divider()
                BehaviourToggle(title: "Keep tiled and Split View windows sharp", value: $settings.keepTiledWindowsSharp)
                Divider()
                BehaviourToggle(title: "Turn off in full-screen apps", value: $settings.disableInFullScreen)
                Divider()
                BehaviourToggle(title: "Turn off while sharing or presenting", value: $settings.disableWhileSharing)
                Divider()
                BehaviourToggle(title: "Fade the desktop when no window is focused", value: $settings.fadeDesktopWhenUnfocused)
                Divider()
                Text("The menu bar and the Dock always stay sharp. Sharing also hides the overlay from most screen captures.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            SectionTitle(text: "Peek")
            Card {
                Row(title: "Bring a window back while the cursor rests on it") {
                    Toggle("", isOn: $settings.peekEnabled).labelsHidden()
                }
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Delay")
                        Spacer()
                        Text("Fast").font(.caption).foregroundStyle(.blue)
                        Slider(value: $settings.peekDelay, in: 0.15...1.5)
                            .frame(width: 200)
                        Text("Patient").font(.caption).foregroundStyle(.blue)
                    }
                    Text("\(String(format: "%.2f", settings.peekDelay))s of resting before a window comes back. It stays back until the cursor leaves it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .panePadding()
        .sheet(isPresented: $showingPresetManager) {
            PresetManagerView().environmentObject(settings)
        }
    }
}

private struct PresetChip: View {
    var name: String
    var isActive: Bool
    var action: () -> Void
    var body: some View {
        Button(name, action: action)
            .buttonStyle(.bordered)
            .tint(isActive ? .accentColor : .primary)
    }
}

private struct IntensityRow: View {
    var icon: String
    var title: String
    @Binding var value: Double
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(title)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .foregroundStyle(.blue)
                    .monospacedDigit()
            }
            Slider(value: $value, in: 0...1)
        }
        .padding(.vertical, 6)
    }
}

private struct BehaviourToggle: View {
    var title: String
    @Binding var value: Bool
    var body: some View {
        Row(title: title) {
            Toggle("", isOn: $value).labelsHidden()
        }
    }
}

private struct PreviewCard: View {
    @EnvironmentObject private var settings: FloBlurSettings
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.7), .orange.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: CGFloat(settings.blurIntensity * 24))
            .overlay(Color.black.opacity(settings.dimIntensity * 0.6))
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 200, height: 120)
                .shadow(radius: 8)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 7, height: 7)
                            Circle().fill(.yellow).frame(width: 7, height: 7)
                            Circle().fill(.green).frame(width: 7, height: 7)
                        }
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.25))
                                .frame(height: 5)
                        }
                    }
                    .padding(10)
                    .frame(width: 200, alignment: .leading)
                }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Displays

private struct DisplaysPane: View {
    @EnvironmentObject private var settings: FloBlurSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Card {
                Row(title: "Fade only the display with the active window") {
                    Toggle("", isOn: $settings.fadeOnlyActiveDisplay).labelsHidden()
                }
                Divider()
                Text("On a single display this changes nothing. With a second one, it leaves whatever you are reading over there sharp instead of asking you to pin the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(NSScreen.screens, id: \.self) { screen in
                DisplayCard(screen: screen)
            }
            Text("Settings follow the monitor, not the port: unplugging one and plugging it back in keeps what you set for it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .panePadding()
    }
}

private struct DisplayCard: View {
    @EnvironmentObject private var settings: FloBlurSettings
    var screen: NSScreen

    private var key: String { displayID(screen).uuidString }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(screen.localizedName).font(.title3)
                Spacer()
                Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height))")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
            Card {
                Row(title: "Never fade this display") {
                    Toggle("", isOn: neverFadeBinding).labelsHidden()
                }
                Divider()
                DisplayIntensityRow(
                    icon: "drop.fill",
                    title: "Blur",
                    global: settings.blurIntensity,
                    override: overrideBinding(\.blurIntensity)
                )
                Divider()
                DisplayIntensityRow(
                    icon: "circle.lefthalf.filled",
                    title: "Dim",
                    global: settings.dimIntensity,
                    override: overrideBinding(\.dimIntensity)
                )
            }
        }
    }

    private var neverFadeBinding: Binding<Bool> {
        Binding(
            get: { settings.displayOverrides[key]?.neverFade ?? false },
            set: { newValue in
                var o = settings.displayOverrides[key] ?? DisplayOverride()
                o.neverFade = newValue
                settings.displayOverrides[key] = o
            }
        )
    }

    private func overrideBinding(_ keyPath: WritableKeyPath<DisplayOverride, Double?>) -> Binding<Double?> {
        Binding(
            get: { settings.displayOverrides[key]?[keyPath: keyPath] },
            set: { newValue in
                var o = settings.displayOverrides[key] ?? DisplayOverride()
                o[keyPath: keyPath] = newValue
                settings.displayOverrides[key] = o
            }
        )
    }

    private func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

private struct DisplayIntensityRow: View {
    var icon: String
    var title: String
    var global: Double
    @Binding var override: Double?

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(title)
                Spacer()
                Text("\(Int(((override ?? global) * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    override = nil // reset dot: follow the global slider again
                } label: {
                    Image(systemName: override == nil ? "circle.dotted" : "arrow.counterclockwise.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Follow the global slider")
            }
            Slider(
                value: Binding(
                    get: { override ?? global },
                    set: { override = $0 }
                ),
                in: 0...1
            )
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Timing

private struct TimingPane: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @EnvironmentObject private var scheduler: FocusScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Working hours")
            Card {
                Row(title: "Turn the effect on during working hours") {
                    Toggle("", isOn: $settings.scheduleEnabled).labelsHidden()
                }
                Divider()
                HStack {
                    Text("From")
                    DatePicker("", selection: timeBinding($settings.scheduleStartMinutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("To")
                    DatePicker("", selection: timeBinding($settings.scheduleEndMinutes), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer()
                }
                .padding(.vertical, 6)
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { day in
                        WeekdayChip(
                            label: shortWeekday(day),
                            isOn: settings.scheduleWeekdays.contains(day)
                        ) {
                            if let i = settings.scheduleWeekdays.firstIndex(of: day) {
                                settings.scheduleWeekdays.remove(at: i)
                            } else {
                                settings.scheduleWeekdays.append(day)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                Divider()
                Row(title: "Preset") {
                    Picker("", selection: $settings.schedulePresetID) {
                        Text("Keep the current look").tag(nil as String?)
                        ForEach(settings.allPresets) { preset in
                            Text(preset.name).tag(preset.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Divider()
                Text(scheduler.scheduleActive
                    ? "On — the effect follows the schedule."
                    : "Off — the effect only follows the menu, the shortcut and the cursor shake.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            SectionTitle(text: "Focus sessions")
            Card {
                HStack {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(scheduler.phase == .idle ? "No session running" : (scheduler.sessionLabel ?? ""))
                            .font(.headline)
                        Text("\(settings.pomodoroFocusMinutes) min of focus, then \(settings.pomodoroBreakMinutes) min away")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if scheduler.phase == .idle {
                        Button("Start") { scheduler.startSession() }
                    } else {
                        Button("Stop") { scheduler.stopSession() }
                    }
                }
                .padding(.vertical, 8)
                Divider()
                StepperRow(title: "Focus round", value: $settings.pomodoroFocusMinutes, range: 5...120, unit: "min")
                Divider()
                StepperRow(title: "Break", value: $settings.pomodoroBreakMinutes, range: 1...60, unit: "min")
                Divider()
                StepperRow(title: "Long break", value: $settings.pomodoroLongBreakMinutes, range: 5...90, unit: "min")
                Divider()
                StepperRow(title: "Long break after", value: $settings.pomodoroRounds, range: 2...8, unit: "rounds")
                Divider()
                Row(title: "Preset while focusing") {
                    Picker("", selection: $settings.pomodoroPresetID) {
                        Text("Keep the current look").tag(nil as String?)
                        ForEach(settings.allPresets) { preset in
                            Text(preset.name).tag(preset.id as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                Divider()
                Row(title: "Roll straight into the next phase") {
                    Toggle("", isOn: $settings.pomodoroContinuesAutomatically).labelsHidden()
                }
                Divider()
                Text("Breaks switch the effect off, so stepping away actually looks like a break. With this off, each phase waits for you to start it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            SectionTitle(text: "Shortcuts")
            Text("Sessions can also be driven from Shortcuts, or with Open URL floblur://pomodoro/start, floblur://pomodoro/skip and floblur://pomodoro/stop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .panePadding()
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = minutes.wrappedValue / 60
                comps.minute = minutes.wrappedValue % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    private func shortWeekday(_ day: Int) -> String {
        ["S", "M", "T", "W", "T", "F", "S"][day - 1]
    }
}

private struct WeekdayChip: View {
    var label: String
    var isOn: Bool
    var action: () -> Void
    var body: some View {
        Button(label, action: action)
            .frame(width: 40, height: 28)
            .background(RoundedRectangle(cornerRadius: 6).fill(isOn ? Color.accentColor : Color.primary.opacity(0.08)))
            .foregroundStyle(isOn ? .white : .secondary)
            .buttonStyle(.plain)
    }
}

private struct StepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String
    var body: some View {
        HStack {
            Text("\(title): \(value) \(unit)")
            Spacer()
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Apps

private struct AppsPane: View {
    @EnvironmentObject private var settings: FloBlurSettings

    enum Tab: Hashable {
        case pause, sharp, auto
    }

    @State private var tab = Tab.pause

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $tab) {
                Text("Pause effect").tag(Tab.pause)
                Text("Always sharp").tag(Tab.sharp)
                Text("Auto presets").tag(Tab.auto)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 420)
            Text(explainer)
                .font(.callout)
                .foregroundStyle(.secondary)
            AppTable(tab: tab)
        }
        .panePadding()
    }

    private var explainer: String {
        switch tab {
        case .pause: return "While one of these apps is in front, FloBlur fades nothing."
        case .sharp: return "These apps always stay sharp, wherever they are."
        case .auto: return "Bring an assigned app to the front and its preset is applied instantly. Each app can belong to one preset."
        }
    }
}

private struct AppTable: View {
    @EnvironmentObject private var settings: FloBlurSettings
    var tab: AppsPane.Tab

    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List {
                ForEach(bundleIDs, id: \.self) { bid in
                    HStack {
                        AppIcon(bundleID: bid)
                        Text(AppInfo.name(for: bid))
                        Spacer()
                        if tab == .auto {
                            Picker("", selection: autoPresetBinding(bid)) {
                                ForEach(settings.allPresets) { preset in
                                    Text(preset.name).tag(preset.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 160)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = bid }
                    .listRowBackground(selection == bid ? Color.accentColor.opacity(0.25) : nil)
                }
            }
            .frame(height: 300)
            HStack {
                Button("Add…") { addApp() }
                Button("Remove") { removeSelected() }
                    .disabled(selection == nil)
            }
            if tab == .pause {
                Text("Tip: the front app can also be added from the menu bar popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var bundleIDs: [String] {
        switch tab {
        case .pause: return settings.excludedBundleIDs
        case .sharp: return settings.alwaysSharpBundleIDs
        case .auto: return Array(settings.automaticPresetByBundleID.keys).sorted()
        }
    }

    private func autoPresetBinding(_ bid: String) -> Binding<String> {
        Binding(
            get: { settings.automaticPresetByBundleID[bid] ?? FocusPreset.builtins[0].id },
            set: { settings.automaticPresetByBundleID[bid] = $0 }
        )
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bid = Bundle(url: url)?.bundleIdentifier else { continue }
            switch tab {
            case .pause:
                if !settings.excludedBundleIDs.contains(bid) {
                    settings.excludedBundleIDs.append(bid)
                }
            case .sharp:
                if !settings.alwaysSharpBundleIDs.contains(bid) {
                    settings.alwaysSharpBundleIDs.append(bid)
                }
            case .auto:
                if settings.automaticPresetByBundleID[bid] == nil {
                    settings.automaticPresetByBundleID[bid] = FocusPreset.builtins[0].id
                }
            }
        }
    }

    private func removeSelected() {
        guard let selection else { return }
        switch tab {
        case .pause: settings.excludedBundleIDs.removeAll { $0 == selection }
        case .sharp: settings.alwaysSharpBundleIDs.removeAll { $0 == selection }
        case .auto: settings.automaticPresetByBundleID[selection] = nil
        }
        self.selection = nil
    }
}

private enum AppInfo {
    static func name(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url),
           let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return bundleID
    }

    static func fileURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("FloBlur").font(.title2)
                    Text(versionString)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            Text("One clear window. A free and open-source focus effect for your Mac: keep the window you're using sharp and soften everything behind it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
        .panePadding()
    }

    private var versionString: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Version \(short) (\(build))"
    }
}

private struct AppIcon: View {    var bundleID: String
    var body: some View {
        Group {
            if let url = AppInfo.fileURL(for: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
            }
        }
        .frame(width: 20, height: 20)
    }
}
