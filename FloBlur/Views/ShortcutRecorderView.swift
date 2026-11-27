import SwiftUI
import AppKit
import Carbon

/// Records a complete combination before asking the app to save it.
struct ShortcutRecorderView: NSViewRepresentable {
    @EnvironmentObject private var app: AppDelegate
    var combo: HotKeyCombo?
    var onRecord: (HotKeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton(frame: .zero)
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.savedTitle = combo?.displayString ?? "Set…"
        button.onRecord = onRecord
        button.onRecordingChange = app.setShortcutRecordingHandler
    }

    final class RecorderButton: NSButton {
        var onRecord: ((HotKeyCombo) -> Void)?
        var onRecordingChange: ((((HotKeyCombo) -> Bool)?) -> Void)?
        var savedTitle = "" {
            didSet { updateTitle() }
        }
        private var isRecording = false {
            didSet {
                guard isRecording != oldValue else { return }
                updateTitle()
                if isRecording {
                    onRecordingChange? { [weak self] combo in
                        guard let self, self.isRecording, self.window?.isKeyWindow == true else { return false }
                        self.finishRecording(combo)
                        return true
                    }
                } else {
                    onRecordingChange?(nil)
                }
            }
        }

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
            isRecording = window?.makeFirstResponder(self) == true
        }

        private func updateTitle() {
            title = isRecording ? "Type shortcut…" : savedTitle
        }

        override var acceptsFirstResponder: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording, window?.firstResponder === self else {
                return super.performKeyEquivalent(with: event)
            }
            keyDown(with: event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == kVK_Escape {
                isRecording = false
                return
            }
            let modifiers = HotKeyCombo.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return }
            finishRecording(HotKeyCombo(keyCode: Int(event.keyCode), modifiers: modifiers))
        }

        private func finishRecording(_ combo: HotKeyCombo) {
            isRecording = false
            onRecord?(combo)
        }

        override func resignFirstResponder() -> Bool {
            isRecording = false
            return super.resignFirstResponder()
        }
    }
}
