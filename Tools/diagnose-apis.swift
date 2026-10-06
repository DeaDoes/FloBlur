import AppKit

// FloBlur private-API diagnostic. Standalone scratch tool — NOT part of the
// app target. Compile + run from the repo root:
//
//   swiftc -o /tmp/floblur_diag Tools/diagnose-apis.swift -framework AppKit && /tmp/floblur_diag
//
// Prints which legs the effect stands on. No windows created, nothing changed.
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("---")

// 1. SkyLight background-blur symbols
do {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    print("SkyLight framework loads: \(handle != nil)")
    if handle != nil {
        typealias ConnFn = @convention(c) () -> Int32
        let conn = dlsym(handle, "CGSMainConnectionID").map {
            unsafeBitCast($0, to: ConnFn.self)()
        } ?? 0
        print("CGSMainConnectionID nonzero: \(conn != 0)")
        let hasCGS = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") != nil
        let hasSLS = dlsym(handle, "SLSSetWindowBackgroundBlurRadius") != nil
        print("CGSSetWindowBackgroundBlurRadius present: \(hasCGS)")
        print("SLSSetWindowBackgroundBlurRadius present: \(hasSLS)")
        print("=> blur leg: \((conn != 0 && (hasCGS || hasSLS)) ? "ALIVE" : "DEAD — blur falls back to dim-only")")
    } else {
        print("=> blur leg: DEAD — blur falls back to dim-only")
    }
}
print("---")

// 2. Night Shift status path
do {
    let hw = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
    print("CoreBrightness loads: \(hw != nil)")
    let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type
    print("CBBlueLightClient exists: \(cls != nil)")
    let sel = NSSelectorFromString("getBlueLightStatus:")
    if let client = cls?.init() {
        print("responds to getBlueLightStatus:: \(client.responds(to: sel))")
    }
    // NOTE: a strength of 0 right now can mean "Night Shift is off at this
    // moment". Rerun with Night Shift manually ON to separate off-vs-missing.
    print("=> warm-follow leg: \((cls != nil) ? "WIRED (strength shown by app at runtime)" : "DEAD — toggle stays neutral")")
}
print("---")

// 3. Window-list + Dock-name heuristics (no permission needed)
do {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        print("window list fetch: FAILED"); exit(0)
    }
    print("window list fetch: OK (\(list.count) entries)")
    let dockNames = list.compactMap { d -> String? in
        guard (d[kCGWindowOwnerName as String] as? String) == "Dock" else { return nil }
        return d[kCGWindowName as String] as? String
    }
    print("Dock windows visible: \(dockNames.count)")
    let mcNames = dockNames.filter { $0.contains("Mission Control") || $0.contains("Exposé") || $0.contains("Expose") }
    print("Mission Control markers now: \(mcNames.isEmpty ? "none (expected — MC not active)" : mcNames.joined(separator: ", "))")
    print("=> MC/expose leg: ALIVE (heuristic active; trigger MC and re-check markers if in doubt)")
}
