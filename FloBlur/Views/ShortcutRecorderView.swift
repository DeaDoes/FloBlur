import SwiftUI
import AppKit
import Carbon

/// Click-to-record key-combination field, mirroring the original's
/// "Combination ⌥⌘B" recorder. Stores a Carbon key code + modifiers.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: UInt

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = { context.coordinator.recording = true }
        button.coordinator = context.coordinator
        return button
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.title = HotKeyLabel.string(keyCode: keyCode, modifiers: modifiers)
        view.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(keyCode: $keyCode, modifiers: $modifiers)
    }

    final class Coordinator: NSObject {
        @Binding var keyCode: Int
        @Binding var modifiers: UInt
        var recording = false {
            didSet { recordingChanged?() }
        }

        var recordingChanged: (() -> Void)?

        init(keyCode: Binding<Int>, modifiers: Binding<UInt>) {
            _keyCode = keyCode
            _modifiers = modifiers
        }
    }

    final class RecorderButton: NSButton {
        var onRecord: (() -> Void)?
        weak var coordinator: Coordinator? {
            didSet {
                coordinator?.recordingChanged = { [weak self] in
                    DispatchQueue.main.async { self?.updateAppearance() }
                }
            }
        }

        var isRecording: Bool { coordinator?.recording ?? false }

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            target = self
            action = #selector(beginRecording)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        @objc private func beginRecording() {
            onRecord?()
            needsDisplay = true
            window?.makeFirstResponder(self)
        }

        private func updateAppearance() {
            if isRecording {
                title = "Type shortcut…"
            }
            needsDisplay = true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording, let coordinator else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 { // Escape cancels
                coordinator.recording = false
                return
            }
            var mods: UInt = 0
            let flags = event.modifierFlags
            if flags.contains(.control) { mods |= UInt(controlKey) }
            if flags.contains(.option) { mods |= UInt(optionKey) }
            if flags.contains(.shift) { mods |= UInt(shiftKey) }
            if flags.contains(.command) { mods |= UInt(cmdKey) }
            guard mods != 0 else { return } // a bare key is not a shortcut
            coordinator.keyCode = Int(event.keyCode)
            coordinator.modifiers = mods
            coordinator.recording = false
        }

        override func resignFirstResponder() -> Bool {
            coordinator?.recording = false
            return super.resignFirstResponder()
        }
    }
}
