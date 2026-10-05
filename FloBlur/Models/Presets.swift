import Foundation

/// A named look: effect style + intensities + app lists. The four built-ins
/// mirror the original app's Coding / Reading / Presenting / Deep Focus
/// presets. A preset stores the style, the intensities, the colour, and the
/// app lists — applying one restores all of them.
struct FocusPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var style: FocusStyle
    var blurIntensity: Double
    var dimIntensity: Double
    var dimTint: DimTint
    var dimTintCustom: String
    var excludedBundleIDs: [String]
    var alwaysSharpBundleIDs: [String]

    init(
        id: String,
        name: String,
        style: FocusStyle,
        blurIntensity: Double,
        dimIntensity: Double,
        dimTint: DimTint = .neutral,
        dimTintCustom: String = "",
        excludedBundleIDs: [String] = [],
        alwaysSharpBundleIDs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.blurIntensity = blurIntensity
        self.dimIntensity = dimIntensity
        self.dimTint = dimTint
        self.dimTintCustom = dimTintCustom
        self.excludedBundleIDs = excludedBundleIDs
        self.alwaysSharpBundleIDs = alwaysSharpBundleIDs
    }

    static let coding = FocusPreset(
        id: "coding", name: "Coding",
        style: .both, blurIntensity: 0.65, dimIntensity: 0.30
    )
    static let reading = FocusPreset(
        id: "reading", name: "Reading",
        style: .blur, blurIntensity: 0.88, dimIntensity: 0.0
    )
    static let presenting = FocusPreset(
        id: "presenting", name: "Presenting",
        style: .dim, blurIntensity: 0.0, dimIntensity: 0.30
    )
    static let deepFocus = FocusPreset(
        id: "deep-focus", name: "Deep Focus",
        style: .both, blurIntensity: 0.85, dimIntensity: 0.55
    )

    static let builtins: [FocusPreset] = [.coding, .reading, .presenting, .deepFocus]

    var isBuiltin: Bool { Self.builtins.contains { $0.id == id } }
}
