import AppKit
import Carbon

/// A stored key combination: Carbon key code + Carbon modifiers.
/// Mapping verified against the original (`command→0x100, option→0x800,
/// control→0x1000, shift→0x200`).
struct HotKeyCombo: Codable, Equatable, Hashable {
    var keyCode: Int
    var modifiers: UInt

    /// NSEvent modifier flags → Carbon modifiers.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt {
        var mods: UInt = 0
        if flags.contains(.control) { mods |= UInt(controlKey) }
        if flags.contains(.option) { mods |= UInt(optionKey) }
        if flags.contains(.shift) { mods |= UInt(shiftKey) }
        if flags.contains(.command) { mods |= UInt(cmdKey) }
        return mods
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt(cmdKey) != 0 { s += "⌘" }
        s += HotKeyLabel.keyName(keyCode: keyCode)
        return s
    }
}

/// Global keyboard shortcuts (default ⌥⌘B) via Carbon hotkeys — no
/// Accessibility permission needed. Supports the main toggle plus one
/// hotkey per preset; duplicate combos resolve first-wins.
final class HotKeyManager {
    private var refs: [Int: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private var fires: [Int: () -> Void] = [:]

    private static var sharedFires: [Int: () -> Void] = [:]

    init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotID
                )
                // Carbon handlers run off the main thread: hop over before
                // touching settings/UI, or @Published updates tear.
                if let fire = HotKeyManager.sharedFires[Int(hotID.id)] {
                    DispatchQueue.main.async(execute: fire)
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &handlerRef
        )
    }

    deinit {
        for ref in refs.values {
            UnregisterEventHotKey(ref)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    /// Reconciles registrations: id 1 is the main toggle, 1000+i are presets.
    func sync(main: (combo: HotKeyCombo, enabled: Bool)?, presets: [(id: Int, combo: HotKeyCombo, fire: () -> Void)], mainFire: @escaping () -> Void) {
        var wanted: [Int: (HotKeyCombo, () -> Void)] = [:]
        var seenCombos = Set<HotKeyCombo>()
        if let main, main.enabled {
            wanted[1] = (main.combo, mainFire)
            seenCombos.insert(main.combo)
        }
        for preset in presets {
            guard !seenCombos.contains(preset.combo) else { continue } // first wins
            seenCombos.insert(preset.combo)
            wanted[preset.id] = (preset.combo, preset.fire)
        }
        for id in refs.keys where wanted[id] == nil {
            if let ref = refs[id] {
                UnregisterEventHotKey(ref)
            }
            refs[id] = nil
            fires[id] = nil
        }
        for (id, entry) in wanted {
            // Re-register when the combo changed (or is new).
            unregister(id: id)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(entry.0.keyCode),
                UInt32(entry.0.modifiers),
                EventHotKeyID(signature: OSType(0x464C4252), id: UInt32(id)),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else { continue }
            refs[id] = ref
            fires[id] = entry.1
        }
        Self.sharedFires = fires
    }

    private func unregister(id: Int) {
        if let ref = refs[id] {
            UnregisterEventHotKey(ref)
            refs[id] = nil
        }
        fires[id] = nil
    }
}

/// Human-readable label for a Carbon key combo, e.g. "⌥⌘B".
enum HotKeyLabel {
    static func string(keyCode: Int, modifiers: UInt) -> String {
        HotKeyCombo(keyCode: keyCode, modifiers: modifiers).displayString
    }

    static func keyName(keyCode: Int) -> String {
        // kVK_ANSI_* codes for everything a shortcut recorder can produce.
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Grave: return "`"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "key \(keyCode)"
        }
    }
}
