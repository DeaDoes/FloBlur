# FloBlur

One clear window. A free, open-source focus effect for macOS: keep the window
you're using sharp and soften everything behind it with blur, dim, or both.

Inspired by [defocus.me](https://defocus.me). Independent project, no
affiliation. All code here is written from scratch for this repository.

## Features

- **Blur / Dim / Both** background effect with per-display overlays
- **Presets** (Coding, Reading, Presenting, Deep Focus) + custom presets with
  hotkeys, exclusions, and always-sharp apps
- **Menu-bar popover**: preset grid, live sliders, per-app actions, pomodoro
  sessions, updates, settings
- **Full Settings**: General, Appearance (style, colour, behaviour, peek),
  Displays (per-monitor overrides), Timing (working hours, pomodoro),
  Apps (pause / always-sharp / auto-preset lists)
- **Global hotkey** (⌥⌘B) with combo recorder, **cursor-shake** toggle,
  **hover peek**, **Night Shift** wash, **toggle HUD**
- **Pomodoro sessions** + working-hours schedule, `floblur://` URL schemes
- No Screen Recording or Accessibility permission required

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer)
- Xcode 16+ to build

## Build & Run

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
open FloBlur.xcodeproj   # press ⌘R to build & run
```

Or from the command line:

```sh
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Debug build
```

The app lives in the menu bar (no Dock icon). Flip the switch in the popover
to try the effect.

## How it works

One transparent overlay window per display sits directly beneath the active
window and applies background blur (SkyLight, also used with a
`NSVisualEffectView` fallback) plus a tinted dim layer. Sharp regions for
pinned windows are cut as holes. Tracking uses window metadata only
(`CGWindowListCopyWindowInfo` + workspace notifications).

## License

MIT — see [LICENSE](LICENSE).
