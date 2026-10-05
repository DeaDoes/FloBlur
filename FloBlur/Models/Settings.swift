import Foundation
import Combine
import Carbon

/// Effect style, mirroring the original app's `style` key ("blur" / "dim" / "both").
enum FocusStyle: String, CaseIterable, Codable {
    case blur
    case dim
    case both
}

/// Dim wash colour, mirroring the original's `dimTint` key
/// ("neutral" / "warm" / "custom", plus `dimTintCustom` for the custom color).
enum DimTint: String, CaseIterable, Codable {
    case neutral
    case warm
    case custom

    var displayName: String {
        switch self {
        case .neutral: return "Neutral"
        case .warm: return "Warm"
        case .custom: return "Custom"
        }
    }
}

/// Per-display overrides. `nil` intensities mean "follow the global sliders"
/// (the reset dot in the original restores `nil`).
struct DisplayOverride: Codable, Equatable {
    var neverFade: Bool = false
    var blurIntensity: Double?
    var dimIntensity: Double?
}

extension DisplayOverride {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        neverFade = (try? c.decode(Bool.self, forKey: .neverFade)) ?? false
        blurIntensity = try? c.decode(Double.self, forKey: .blurIntensity)
        dimIntensity = try? c.decode(Double.self, forKey: .dimIntensity)
    }
}

/// Central settings store. Keys intentionally match the original app's
/// UserDefaults keys so a future migration can read them 1:1.
final class FloBlurSettings: ObservableObject {
    static let shared = FloBlurSettings(defaults: .standard)

    private let defaults: UserDefaults
    private var applyingPreset = false

    // MARK: Core effect
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }
    @Published var style: FocusStyle {
        didSet {
            defaults.set(style.rawValue, forKey: Keys.style)
            manualChange()
        }
    }
    @Published var blurIntensity: Double {
        didSet {
            defaults.set(blurIntensity, forKey: Keys.blurIntensity)
            manualChange()
        }
    }
    @Published var dimIntensity: Double {
        didSet {
            defaults.set(dimIntensity, forKey: Keys.dimIntensity)
            manualChange()
        }
    }
    @Published var dimTint: DimTint {
        didSet {
            defaults.set(dimTint.rawValue, forKey: Keys.dimTint)
            manualChange()
        }
    }
    @Published var dimTintCustom: String {
        didSet {
            defaults.set(dimTintCustom, forKey: Keys.dimTintCustom)
            manualChange()
        }
    }
    @Published var warmWithNightShift: Bool {
        didSet { defaults.set(warmWithNightShift, forKey: Keys.warmWithNightShift) }
    }
    @Published var activePresetID: String? {
        didSet { defaults.set(activePresetID, forKey: Keys.activePresetID) }
    }
    @Published var customPresets: [FocusPreset] {
        didSet { store(customPresets, forKey: Keys.customPresets) }
    }

    // MARK: Behaviour (Appearance → Behaviour)
    @Published var fadeOtherWindowsOfSameApp: Bool {
        didSet { defaults.set(fadeOtherWindowsOfSameApp, forKey: Keys.fadeOtherWindowsOfSameApp) }
    }
    @Published var keepTiledWindowsSharp: Bool {
        didSet { defaults.set(keepTiledWindowsSharp, forKey: Keys.keepTiledWindowsSharp) }
    }
    @Published var disableInFullScreen: Bool {
        didSet { defaults.set(disableInFullScreen, forKey: Keys.disableInFullScreen) }
    }
    @Published var disableWhileSharing: Bool {
        didSet { defaults.set(disableWhileSharing, forKey: Keys.disableWhileSharing) }
    }
    @Published var fadeDesktopWhenUnfocused: Bool {
        didSet { defaults.set(fadeDesktopWhenUnfocused, forKey: Keys.fadeDesktopWhenUnfocused) }
    }

    // MARK: Peek
    @Published var peekEnabled: Bool {
        didSet { defaults.set(peekEnabled, forKey: Keys.peekEnabled) }
    }
    @Published var peekDelay: Double {
        didSet { defaults.set(peekDelay, forKey: Keys.peekDelay) }
    }

    // MARK: Displays
    @Published var fadeOnlyActiveDisplay: Bool {
        didSet { defaults.set(fadeOnlyActiveDisplay, forKey: Keys.fadeOnlyActiveDisplay) }
    }
    @Published var displayOverrides: [String: DisplayOverride] {
        didSet { store(displayOverrides, forKey: Keys.displayOverrides) }
    }

    // MARK: Apps
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs) }
    }
    @Published var alwaysSharpBundleIDs: [String] {
        didSet { defaults.set(alwaysSharpBundleIDs, forKey: Keys.alwaysSharpBundleIDs) }
    }
    @Published var automaticPresetByBundleID: [String: String] {
        didSet { defaults.set(automaticPresetByBundleID, forKey: Keys.automaticPresetByBundleID) }
    }
    @Published var presetHotKeys: [String: HotKeyCombo] {
        didSet { store(presetHotKeys, forKey: Keys.presetHotKeys) }
    }

    // MARK: General
    @Published var shakeEnabled: Bool {
        didSet { defaults.set(shakeEnabled, forKey: Keys.shakeEnabled) }
    }
    @Published var shakeSensitivity: Double {
        didSet { defaults.set(shakeSensitivity, forKey: Keys.shakeSensitivity) }
    }
    @Published var shortcutEnabled: Bool {
        didSet { defaults.set(shortcutEnabled, forKey: Keys.shortcutEnabled) }
    }
    @Published var shortcutKeyCode: Int {
        didSet { defaults.set(shortcutKeyCode, forKey: Keys.shortcutKeyCode) }
    }
    @Published var shortcutModifiers: UInt {
        didSet { defaults.set(UInt(shortcutModifiers), forKey: Keys.shortcutModifiers) }
    }
    @Published var checkUpdatesAutomatically: Bool {
        didSet { defaults.set(checkUpdatesAutomatically, forKey: Keys.checkUpdatesAutomatically) }
    }
    @Published var downloadUpdatesAutomatically: Bool {
        didSet { defaults.set(downloadUpdatesAutomatically, forKey: Keys.downloadUpdatesAutomatically) }
    }

    // MARK: Timing
    @Published var scheduleEnabled: Bool {
        didSet { defaults.set(scheduleEnabled, forKey: Keys.scheduleEnabled) }
    }
    @Published var scheduleStartMinutes: Int {
        didSet { defaults.set(scheduleStartMinutes, forKey: Keys.scheduleStartMinutes) }
    }
    @Published var scheduleEndMinutes: Int {
        didSet { defaults.set(scheduleEndMinutes, forKey: Keys.scheduleEndMinutes) }
    }
    @Published var scheduleWeekdays: [Int] {
        didSet { defaults.set(scheduleWeekdays, forKey: Keys.scheduleWeekdays) }
    }
    @Published var schedulePresetID: String? {
        didSet { defaults.set(schedulePresetID, forKey: Keys.schedulePresetID) }
    }
    @Published var pomodoroFocusMinutes: Int {
        didSet { defaults.set(pomodoroFocusMinutes, forKey: Keys.pomodoroFocusMinutes) }
    }
    @Published var pomodoroBreakMinutes: Int {
        didSet { defaults.set(pomodoroBreakMinutes, forKey: Keys.pomodoroBreakMinutes) }
    }
    @Published var pomodoroLongBreakMinutes: Int {
        didSet { defaults.set(pomodoroLongBreakMinutes, forKey: Keys.pomodoroLongBreakMinutes) }
    }
    @Published var pomodoroRounds: Int {
        didSet { defaults.set(pomodoroRounds, forKey: Keys.pomodoroRounds) }
    }
    @Published var pomodoroPresetID: String? {
        didSet { defaults.set(pomodoroPresetID, forKey: Keys.pomodoroPresetID) }
    }
    @Published var pomodoroContinuesAutomatically: Bool {
        didSet {
            defaults.set(pomodoroContinuesAutomatically, forKey: Keys.pomodoroContinuesAutomatically)
        }
    }

    // MARK: Presets

    var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Keys.hasCompletedOnboarding)
    }

    var allPresets: [FocusPreset] { FocusPreset.builtins + customPresets }

    func preset(id: String?) -> FocusPreset? {
        allPresets.first { $0.id == id }
    }

    /// Blur radius for a display: 0 unless the style includes blur, else the
    /// (possibly per-display) intensity mapped to 0...80.
    func effectiveBlurRadius(forDisplay key: String) -> Int {
        guard style == .blur || style == .both else { return 0 }
        let v: Double
        if let overrideValue = displayOverrides[key]?.blurIntensity {
            v = overrideValue
        } else {
            v = blurIntensity
        }
        guard v > 0 else { return 0 }
        return Int((min(max(v, 0), 1) * 80).rounded())
    }

    /// Dim opacity for a display: the (possibly per-display) intensity.
    func effectiveDimOpacity(forDisplay key: String) -> Double {
        let v = displayOverrides[key]?.dimIntensity ?? dimIntensity
        return min(max(v, 0), 1)
    }

    /// Applies a preset's look and marks it active. Editing any intensity
    /// afterwards clears the active mark (custom look).
    func applyPreset(_ preset: FocusPreset) {
        applyingPreset = true
        style = preset.style
        blurIntensity = preset.blurIntensity
        dimIntensity = preset.dimIntensity
        dimTint = preset.dimTint
        if !preset.dimTintCustom.isEmpty {
            dimTintCustom = preset.dimTintCustom
        }
        excludedBundleIDs = preset.excludedBundleIDs
        alwaysSharpBundleIDs = preset.alwaysSharpBundleIDs
        applyingPreset = false
        activePresetID = preset.id
    }

    private func manualChange() {
        if !applyingPreset {
            activePresetID = nil
        }
    }

    // MARK: Init

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.isEnabled: false,
            Keys.style: FocusStyle.both.rawValue,
            Keys.blurIntensity: 0.65,
            Keys.dimIntensity: 0.30,
            Keys.dimTint: DimTint.neutral.rawValue,
            Keys.warmWithNightShift: false,
            Keys.excludedBundleIDs: [String](),
            Keys.alwaysSharpBundleIDs: [String](),
            Keys.automaticPresetByBundleID: [String: String](),
            Keys.fadeOtherWindowsOfSameApp: true,
            Keys.keepTiledWindowsSharp: true,
            Keys.disableInFullScreen: true,
            Keys.disableWhileSharing: true,
            Keys.fadeDesktopWhenUnfocused: false,
            Keys.peekEnabled: true,
            Keys.peekDelay: 0.45,
            Keys.fadeOnlyActiveDisplay: false,
            Keys.shakeEnabled: false,
            Keys.shakeSensitivity: 0.5,
            Keys.shortcutEnabled: true,
            Keys.shortcutKeyCode: 11, // kVK_ANSI_B
            Keys.shortcutModifiers: UInt(0), // resolved below
            Keys.checkUpdatesAutomatically: true,
            Keys.downloadUpdatesAutomatically: true,
            Keys.scheduleEnabled: false,
            Keys.scheduleStartMinutes: 9 * 60,
            Keys.scheduleEndMinutes: 18 * 60,
            Keys.scheduleWeekdays: [2, 3, 4, 5, 6], // Mon–Fri
            Keys.pomodoroFocusMinutes: 25,
            Keys.pomodoroBreakMinutes: 5,
            Keys.pomodoroLongBreakMinutes: 15,
            Keys.pomodoroRounds: 4,
            Keys.pomodoroPresetID: FocusPreset.deepFocus.id,
            Keys.pomodoroContinuesAutomatically: true,
        ])
        isEnabled = defaults.bool(forKey: Keys.isEnabled)
        style = FocusStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .both
        blurIntensity = defaults.double(forKey: Keys.blurIntensity)
        dimIntensity = defaults.double(forKey: Keys.dimIntensity)
        dimTint = DimTint(rawValue: defaults.string(forKey: Keys.dimTint) ?? "") ?? .neutral
        dimTintCustom = defaults.string(forKey: Keys.dimTintCustom) ?? "#3A2A1A"
        warmWithNightShift = defaults.bool(forKey: Keys.warmWithNightShift)
        activePresetID = defaults.string(forKey: Keys.activePresetID)
        customPresets = Self.decode([FocusPreset].self, defaults.string(forKey: Keys.customPresets)) ?? []
        fadeOtherWindowsOfSameApp = defaults.bool(forKey: Keys.fadeOtherWindowsOfSameApp)
        keepTiledWindowsSharp = defaults.bool(forKey: Keys.keepTiledWindowsSharp)
        disableInFullScreen = defaults.bool(forKey: Keys.disableInFullScreen)
        disableWhileSharing = defaults.bool(forKey: Keys.disableWhileSharing)
        fadeDesktopWhenUnfocused = defaults.bool(forKey: Keys.fadeDesktopWhenUnfocused)
        peekEnabled = defaults.bool(forKey: Keys.peekEnabled)
        if defaults.object(forKey: Keys.peekDefaultApplied) == nil {
            // Hover-reveal on by default (matches how the effect is used).
            // Runs once: an explicit user choice afterwards is respected.
            peekEnabled = true
            defaults.set(true, forKey: Keys.peekEnabled)
            defaults.set(true, forKey: Keys.peekDefaultApplied)
        }
        peekDelay = defaults.double(forKey: Keys.peekDelay)
        fadeOnlyActiveDisplay = defaults.bool(forKey: Keys.fadeOnlyActiveDisplay)
        displayOverrides = Self.decode([String: DisplayOverride].self, defaults.string(forKey: Keys.displayOverrides)) ?? [:]
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
        alwaysSharpBundleIDs = defaults.stringArray(forKey: Keys.alwaysSharpBundleIDs) ?? []
        automaticPresetByBundleID = (defaults.dictionary(forKey: Keys.automaticPresetByBundleID) as? [String: String]) ?? [:]
        presetHotKeys = Self.decode([String: HotKeyCombo].self, defaults.string(forKey: Keys.presetHotKeys)) ?? [:]
        shakeEnabled = defaults.bool(forKey: Keys.shakeEnabled)
        shakeSensitivity = defaults.double(forKey: Keys.shakeSensitivity)
        shortcutEnabled = defaults.bool(forKey: Keys.shortcutEnabled)
        let savedMods = defaults.integer(forKey: Keys.shortcutModifiers)
        shortcutKeyCode = defaults.integer(forKey: Keys.shortcutKeyCode)
        // Carbon modifiers (cmdKey/optionKey), NOT NSEvent raw values. Earlier
        // builds persisted NSEvent values (0x180000), which Carbon reads as
        // "no modifiers" — hijacking bare keypresses. Migrate those too.
        let fallback = UInt(cmdKey) | UInt(optionKey) // ⌥⌘
        if savedMods == 0 || savedMods == ((1 << 19) | (1 << 20)) {
            shortcutModifiers = fallback
        } else {
            shortcutModifiers = UInt(savedMods)
        }
        checkUpdatesAutomatically = defaults.bool(forKey: Keys.checkUpdatesAutomatically)
        downloadUpdatesAutomatically = defaults.bool(forKey: Keys.downloadUpdatesAutomatically)
        scheduleEnabled = defaults.bool(forKey: Keys.scheduleEnabled)
        scheduleStartMinutes = defaults.integer(forKey: Keys.scheduleStartMinutes)
        scheduleEndMinutes = defaults.integer(forKey: Keys.scheduleEndMinutes)
        scheduleWeekdays = defaults.array(forKey: Keys.scheduleWeekdays) as? [Int] ?? [2, 3, 4, 5, 6]
        schedulePresetID = defaults.string(forKey: Keys.schedulePresetID)
        pomodoroFocusMinutes = defaults.integer(forKey: Keys.pomodoroFocusMinutes)
        pomodoroBreakMinutes = defaults.integer(forKey: Keys.pomodoroBreakMinutes)
        pomodoroLongBreakMinutes = defaults.integer(forKey: Keys.pomodoroLongBreakMinutes)
        pomodoroRounds = defaults.integer(forKey: Keys.pomodoroRounds)
        pomodoroPresetID = defaults.string(forKey: Keys.pomodoroPresetID)
        pomodoroContinuesAutomatically = defaults.bool(forKey: Keys.pomodoroContinuesAutomatically)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func store<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: key)
        }
    }

    enum Keys {
        static let isEnabled = "isEnabled"
        static let style = "style"
        static let blurIntensity = "blurIntensity"
        static let dimIntensity = "dimIntensity"
        static let dimTint = "dimTint"
        static let dimTintCustom = "dimTintCustom"
        static let warmWithNightShift = "warmWithNightShift"
        static let activePresetID = "activePresetID"
        static let customPresets = "customPresets"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let alwaysSharpBundleIDs = "alwaysSharpBundleIDs"
        static let automaticPresetByBundleID = "automaticPresetByBundleID"
        static let presetHotKeys = "presetHotKeys"
        static let fadeOtherWindowsOfSameApp = "blurOtherWindowsOfSameApp"
        static let keepTiledWindowsSharp = "keepTiledWindowsSharp"
        static let disableInFullScreen = "disableInFullScreen"
        static let disableWhileSharing = "disableWhileSharing"
        static let fadeDesktopWhenUnfocused = "fadeDesktopWhenUnfocused"
        static let peekEnabled = "peekEnabled"
        static let peekDelay = "peekDelay"
        static let peekDefaultApplied = "peekDefaultApplied"
        static let fadeOnlyActiveDisplay = "fadeOnlyActiveDisplay"
        static let displayOverrides = "displayOverrides"
        static let shakeEnabled = "shakeEnabled"
        static let shakeSensitivity = "shakeSensitivity"
        static let shortcutEnabled = "shortcutEnabled"
        static let shortcutKeyCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let checkUpdatesAutomatically = "checkUpdatesAutomatically"
        static let downloadUpdatesAutomatically = "downloadUpdatesAutomatically"
        static let scheduleEnabled = "scheduleEnabled"
        static let scheduleStartMinutes = "scheduleStartMinutes"
        static let scheduleEndMinutes = "scheduleEndMinutes"
        static let scheduleWeekdays = "scheduleWeekdays"
        static let schedulePresetID = "schedulePresetID"
        static let pomodoroFocusMinutes = "pomodoroFocusMinutes"
        static let pomodoroBreakMinutes = "pomodoroBreakMinutes"
        static let pomodoroLongBreakMinutes = "pomodoroLongBreakMinutes"
        static let pomodoroRounds = "pomodoroRounds"
        static let pomodoroPresetID = "pomodoroPresetID"
        static let pomodoroContinuesAutomatically = "pomodoroContinuesAutomatically"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
}
