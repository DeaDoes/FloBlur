import SwiftUI

private struct PresetHotKeyRow: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @EnvironmentObject private var app: AppDelegate
    @State private var shortcutError: String?
    var preset: FocusPreset

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(preset.name)
                Spacer()
                ShortcutRecorderView(combo: settings.presetHotKeys[preset.id]) { combo in
                    shortcutError = app.saveShortcut(combo, for: .preset(preset.id))
                }
                .frame(width: 140)
                if settings.presetHotKeys[preset.id] != nil {
                    Button("Clear") {
                        shortcutError = nil
                        settings.presetHotKeys[preset.id] = nil
                    }
                    .buttonStyle(.link)
                }
            }
            if let warning = shortcutError ?? app.shortcutWarnings[.preset(preset.id)] {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.red)
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
        settings.deleteCustomPreset(id: selected.id)
        selection = nil
    }
}
