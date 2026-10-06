# Changelog

All notable changes to FloBlur are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Release tags are `vMAJOR.MINOR`. The tag must match `MARKETING_VERSION` in
`FloBlur.xcodeproj` — the release workflow fails fast otherwise, so a mistag can
never ship.

## [Unreleased]

Nothing yet. Contributions land here — see [CONTRIBUTING.md](CONTRIBUTING.md).

## [1.0] — 2026

First public release.

### Added

**Effect**
- Blur / Dim / Both background effect, one transparent overlay per display.
- Per-display blur and dim intensities, plus per-display *never fade*.
- Sharp holes for pinned ("always sharp") windows, cut in global coordinates.
- Real background blur through the private SkyLight
  `CGSSetWindowBackgroundBlurRadius` / `SLSSetWindowBackgroundBlurRadius` APIs,
  with an `NSVisualEffectView` fallback and dim-only last resort.
- Hover peek: a window comes back while the cursor rests on it, and re-fades
  after a configurable delay.
- Dim colours: neutral, warm, or a custom hex wash.
- Warm with Night Shift: while enabled, the dim wash turns warm whenever system
  Night Shift is active (detected through `CoreBrightness`'s
  `CBBlueLightClient`).
- Toggle HUD so a change is visible without opening anything.

**Presets & automation**
- Four built-in presets: Coding, Reading, Presenting, Deep Focus.
- Custom presets, each with its own hotkey, exclusions, and always-sharp apps.
- Automatic preset by app, keyed by bundle ID.
- Pomodoro focus sessions: configurable focus / break / long-break lengths,
  rounds before a long break, preset while focusing, optional auto-continue,
  plus pause, resume, and skip, with a menu-bar countdown.
- Working-hours schedule: enabled days, start and end time, and a preset.
- `floblur://` URL scheme: `toggle`, `on`, `off`, `settings`,
  `preset/<id>`, and `pomodoro/start|pause|resume|skip|stop` — usable from
  Shortcuts, Focus automations, Raycast, Alfred, or the shell.

**Interface**
- Menu-bar popover: preset pills, style picker, live intensity sliders, per-app
  actions, session controls, update check, settings, welcome guide, quit.
- Settings window: General, Appearance, Displays, Timing, Apps, About.
- Launch at login via `SMAppService`.
- Global hotkey (default `⌥⌘B`) with an in-app combo recorder, plus one hotkey
  per preset. Carbon registration — no Accessibility permission needed.
- Cursor-shake toggle with a sensitivity slider.
- First-launch onboarding guide, reopenable from the popover.
- Stacking warnings when another FloBlur or a similar defocus app is detected.

**Behaviour**
- Optional: fade the active app's other windows too.
- Optional: keep tiled and Split View windows sharp.
- Optional: turn off in full-screen apps.
- Optional: turn off while sharing or presenting.
- Optional: fade the desktop when nothing is focused.
- Fade only the display holding the active window, or every display.

**Release engineering**
- Automated tag-driven release pipeline: universal signed Release build,
  styled DMG with custom background art, Sparkle update zip with an EdDSA
  signature, GitHub Release, and `appcast.xml` committed back to `main`.
- `Tools/build-dmg.sh`, `Tools/render-dmg-background.swift`,
  `Tools/update-appcast.py`.
- `Tools/diagnose-apis.swift` — standalone diagnostic reporting which private
  APIs are available on the running system.

### Notes

- macOS 14 Sonoma or later. Universal binary (Apple Silicon + Intel).
- **No Screen Recording and no Accessibility permission**, by design: the app
  uses window metadata, never pixel capture.
- No telemetry, analytics, or crash reporting. Preferences are stored only in
  the local `UserDefaults` domain `me.floblur.FloBlur`.
- Releases are self-signed and **not notarized** (that needs paid Apple
  Developer Program membership). First launch on a new Mac requires right-click
  → Open. In-app updates are still verified with Sparkle EdDSA signatures.
- Release builds are re-signed by `Tools/build-dmg.sh` without `--options
  runtime`, so the shipped app is not hardened. With a Team-less self-signed
  identity, library validation would otherwise reject the re-signed
  `Sparkle.framework` and the app would crash-loop at launch on other Macs.

[Unreleased]: https://github.com/DeaDoes/FloBlur/compare/v1.0...HEAD
[1.0]: https://github.com/DeaDoes/FloBlur/releases/tag/v1.0
