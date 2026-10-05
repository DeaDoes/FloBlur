import SwiftUI
import Carbon

private struct PresetHotKeyRow: View {
    @EnvironmentObject private var settings: FloBlurSettings
    var preset: FocusPreset

    @State private var keyCode = 11
    @State private var modifiers: UInt = UInt(cmdKey) | UInt(optionKey)
    @State private var arming = false

    var body: some View {
        HStack {
            Text(preset.name)
            Spacer()
            if let combo = settings.presetHotKeys[preset.id] {
                Text(combo.displayString)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Clear") {
                    settings.presetHotKeys[preset.id] = nil
                }
                .buttonStyle(.link)
            } else if arming {
                ShortcutRecorderView(keyCode: $keyCode, modifiers: $modifiers)
                    .frame(width: 140)
                    .onChange(of: [keyCode, Int(modifiers)]) { _, _ in
                        settings.presetHotKeys[preset.id] = HotKeyCombo(keyCode: keyCode, modifiers: modifiers)
                        arming = false
                        // Sentinel so re-recording the same combo later still commits.
                        keyCode = -1
                        modifiers = 0
                    }
            } else {
                Button("Set…") { arming = true }
            }
        }
    }
}

/// "Manage…" sheet: apply/select presets, save the current look into one,
/// add the current look as a new preset, duplicate, delete.
struct PresetManagerView: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selection: String?
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.title2)
            List(selection: $selection) {
                Section("Built-in") {
                    ForEach(FocusPreset.builtins) { preset in
                        row(preset)
                    }
                }
                if !settings.customPresets.isEmpty {
                    Section("Mine") {
                        ForEach(settings.customPresets) { preset in
                            row(preset)
                        }
                    }
                }
            }
            .frame(height: 260)

            HStack {
                TextField("New preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Add current look") {
                    addCurrentLook()
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Button("Save current look into selected") {
                    saveCurrentLook()
                }
                .disabled(selection == nil)
                Button("Duplicate") {
                    duplicateSelected()
                }
                .disabled(selection == nil || selectedPreset?.isBuiltin == true)
                Button("Delete", role: .destructive) {
                    deleteSelected()
                }
                .disabled(selection == nil || selectedPreset?.isBuiltin == true)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text("A preset stores the style, the intensities, the colour, and the app lists.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("Hotkeys")
                .font(.headline)
            Text("Pressing it applies this preset and turns the effect on.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(settings.allPresets) { preset in
                PresetHotKeyRow(preset: preset)
                    .environmentObject(settings)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var selectedPreset: FocusPreset? {
        settings.allPresets.first { $0.id == selection }
    }

    private func row(_ preset: FocusPreset) -> some View {
        HStack {
            Text(preset.name)
            Spacer()
            if settings.activePresetID == preset.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .tag(preset.id)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            settings.applyPreset(preset)
        }
    }

    private func snapshotCurrentLook(id: String, name: String) -> FocusPreset {
        FocusPreset(
            id: id,
            name: name,
            style: settings.style,
            blurIntensity: settings.blurIntensity,
            dimIntensity: settings.dimIntensity,
            dimTint: settings.dimTint,
            dimTintCustom: settings.dimTintCustom,
            excludedBundleIDs: settings.excludedBundleIDs,
            alwaysSharpBundleIDs: settings.alwaysSharpBundleIDs
        )
    }

    private func addCurrentLook() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let preset = snapshotCurrentLook(id: UUID().uuidString, name: name)
        settings.customPresets.append(preset)
        settings.activePresetID = preset.id
        newPresetName = ""
    }

    private func saveCurrentLook() {
        guard let selected = selectedPreset, !selected.isBuiltin else { return }
        guard let i = settings.customPresets.firstIndex(where: { $0.id == selected.id }) else { return }
        settings.customPresets[i] = snapshotCurrentLook(id: selected.id, name: selected.name)
        settings.activePresetID = selected.id
    }

    private func duplicateSelected() {
        guard let selected = selectedPreset, !selected.isBuiltin else { return }
        var copy = selected
        copy.id = UUID().uuidString
        copy.name += " copy"
        settings.customPresets.append(copy)
        selection = copy.id
    }

    private func deleteSelected() {
        guard let selected = selectedPreset, !selected.isBuiltin else { return }
        settings.customPresets.removeAll { $0.id == selected.id }
        settings.presetHotKeys[selected.id] = nil
        if settings.activePresetID == selected.id {
            settings.activePresetID = nil
        }
        selection = nil
    }
}
