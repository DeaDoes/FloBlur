import SwiftUI
import AppKit

/// Menu-bar popover. Replicates the original's panel: header with status +
/// switch, 2×2 preset grid, inline appearance sliders, per-app rows,
/// session / updates / settings rows, red Quit.
struct MenuPopoverView: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @EnvironmentObject private var store: SnapshotStore
    @EnvironmentObject private var scheduler: FocusScheduler
    @EnvironmentObject private var app: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            presetGrid
            appearance
            Divider()
            stackingWarning
            if frontAppBundleID != nil {
                appRows
            }
            sessionRow
            updaterRow
            settingsRow
            welcomeRow
            quitRow
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            AppIconImage(size: 40, cornerRadius: 9)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("FloBlur")
                        .font(.headline)
                    Circle()
                        .fill(settings.isEnabled ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                }
                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var statusSubtitle: String {
        if !settings.isEnabled { return "Off" }
        if let paused = store.paused.menuSubtitle { return paused }
        if let id = settings.activePresetID, let preset = settings.preset(id: id) {
            return preset.name
        }
        return "On"
    }

    // MARK: - Presets

    private var presetGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESET")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(FocusPreset.builtins) { preset in
                    Button(preset.name) {
                        settings.applyPreset(preset)
                        settings.isEnabled = true
                    }
                    .buttonStyle(PresetPillButton(isActive: settings.activePresetID == preset.id))
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPEARANCE")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $settings.style) {
                Text("Blur").tag(FocusStyle.blur)
                Text("Dim").tag(FocusStyle.dim)
                Text("Both").tag(FocusStyle.both)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            sliderRow(
                icon: "drop.fill",
                label: "Blur",
                value: $settings.blurIntensity,
                percent: Int((settings.blurIntensity * 100).rounded())
            )
            sliderRow(
                icon: "circle.lefthalf.filled",
                label: "Dim",
                value: $settings.dimIntensity,
                percent: Int((settings.dimIntensity * 100).rounded())
            )
        }
    }

    private func sliderRow(icon: String, label: String, value: Binding<Double>, percent: Int) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                Spacer()
                Text("\(percent)%")
                    .foregroundStyle(.blue)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .font(.subheadline)
            Slider(value: value, in: 0...1)
        }
    }

    // MARK: - Rows

    /// Warns when other effects stack on top of ours (the background then
    /// looks black no matter the sliders).
    @ViewBuilder
    private var stackingWarning: some View {
        if store.foreignFloBlurOverlays > 0 {
            Label(
                "Another FloBlur is also running — quit it in Activity Monitor",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if store.defocusRunning {
            Label(
                "defocus.me is also on — quit one of the two",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private var frontAppName: String {
        store.snapshot.activeName ?? "This app"
    }

    private var frontAppBundleID: String? {
        store.snapshot.activeBundleID
    }

    private var appRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let bid = frontAppBundleID {
                Button {
                    toggleMembership(bid, in: \.excludedBundleIDs)
                } label: {
                    Label("Don't fade \(frontAppName)", systemImage: "eye.slash")
                }
                .buttonStyle(PopoverRowButton(isOn: settings.excludedBundleIDs.contains(bid)))
                Button {
                    toggleMembership(bid, in: \.alwaysSharpBundleIDs)
                } label: {
                    Label("Keep \(frontAppName) sharp", systemImage: "pin")
                }
                .buttonStyle(PopoverRowButton(isOn: settings.alwaysSharpBundleIDs.contains(bid)))
            }
        }
    }

    private func toggleMembership(
        _ bid: String,
        in keyPath: ReferenceWritableKeyPath<FloBlurSettings, [String]>
    ) {
        var list = settings[keyPath: keyPath]
        if let i = list.firstIndex(of: bid) {
            list.remove(at: i)
        } else {
            list.append(bid)
        }
        settings[keyPath: keyPath] = list
    }

    private var sessionRow: some View {
        Button {
            if scheduler.phase == .idle {
                scheduler.startSession()
            } else {
                scheduler.stopSession()
            }
        } label: {
            if scheduler.phase == .idle {
                Label("Start a \(settings.pomodoroFocusMinutes)-minute session", systemImage: "timer")
            } else {
                Label(scheduler.sessionLabel ?? "Stop session", systemImage: "stop.circle")
            }
        }
        .buttonStyle(PopoverRowButton(isOn: false))
    }

    private var updaterRow: some View {
        Button {
            UpdateChecker.check()
        } label: {
            Label("Check for Updates…", systemImage: "arrow.down.circle")
        }
        .buttonStyle(PopoverRowButton(isOn: false))
        .disabled(!UpdateChecker.isConfigured)
    }

    private var settingsRow: some View {
        Button {
            openSettings()
        } label: {
            Label("Settings", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(PopoverRowButton(isOn: false))
    }

    private var welcomeRow: some View {
        Button {
            app.showOnboarding()
        } label: {
            Label("Welcome guide", systemImage: "sparkles")
        }
        .buttonStyle(PopoverRowButton(isOn: false))
    }

    private var quitRow: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit FloBlur", systemImage: "power")
        }
        .buttonStyle(PopoverRowButton(isOn: false, tint: .red))
    }
}

// MARK: - Styles

/// App icon with a system-image fallback (e.g. before resources load).
struct AppIconImage: View {
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let nsImage = NSImage(named: "AppIcon") {
                Image(nsImage: nsImage)
                    .resizable()
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: size * 0.75))
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: cornerRadius).fill(Color.primary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

private struct PresetPillButton: ButtonStyle {
    var isActive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isActive ? 0.18 : 0.08))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct PopoverRowButton: ButtonStyle {
    var isOn: Bool
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .labelStyle(.titleAndIcon)
            Spacer()
            if isOn {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .foregroundStyle(tint ?? .primary)
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
