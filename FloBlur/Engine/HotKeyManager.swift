import AppKit
import Carbon

/// A stored key combination: Carbon key code + Carbon modifiers.
/// Mapping verified against the original (`command→0x100, option→0x800,
/// control→0x1000, shift→0x200`).
struct HotKeyCombo: Codable, Equatable, Hashable {
    var keyCode: Int
    var modifiers: UInt

    static let toggleDefault = HotKeyCombo(keyCode: 11, modifiers: UInt(cmdKey) | UInt(optionKey)) // ⌥⌘B

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
                HotKeyManager.sharedFires[Int(hotID.id)]?()
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
        if wanted.isEmpty {
            print("[FloBlur] hotkey registered: none")
        } else if let mainCombo = wanted[1]?.0 {
            print("[FloBlur] hotkey registered: \(mainCombo.displayString) (+\(wanted.count - 1) preset keys)")
        }
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
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        default: return "key \(keyCode)"
        }
    }
}
