<div align="center">

# FloBlur

**One clear window.** A free, open-source focus effect for macOS — keep the
window you're using sharp and soften everything behind it.

[![macOS](https://img.shields.io/badge/macOS-14%20Sonoma%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.0-F05138?logo=swift&logoColor=white)](https://swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build](https://github.com/DeaDoes/FloBlur/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DeaDoes/FloBlur/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/DeaDoes/FloBlur?label=release&sort=semver)](https://github.com/DeaDoes/FloBlur/releases/latest)
[![Contributors](https://img.shields.io/github/contributors/DeaDoes/FloBlur?style=social)](https://github.com/DeaDoes/FloBlur/graphs/contributors)
[![Stars](https://img.shields.io/github/stars/DeaDoes/FloBlur?style=social)](https://github.com/DeaDoes/FloBlur/stargazers)
[![Forks](https://img.shields.io/github/forks/DeaDoes/FloBlur?style=social)](https://github.com/DeaDoes/FloBlur/network/members)
[![Issues](https://img.shields.io/github/issues/DeaDoes/FloBlur?style=social)](https://github.com/DeaDoes/FloBlur/issues)

No Screen Recording. No Accessibility. No account. No telemetry.

</div>

---

## Contents

- [What it does](#what-it-does)
- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [Using FloBlur](#using-floblur)
  - [Menu-bar popover](#menu-bar-popover)
  - [Settings window](#settings-window)
  - [Presets](#presets)
  - [URL scheme (Shortcuts &amp; Focus)](#url-scheme-shortcuts--focus)
  - [Keyboard shortcuts](#keyboard-shortcuts)
- [How it works](#how-it-works)
- [Permissions &amp; privacy](#permissions--privacy)
- [Private APIs](#private-apis)
- [Project layout](#project-layout)
- [Build from source](#build-from-source)
- [Tools](#tools)
- [Releases &amp; auto-update](#releases--auto-update)
- [Contributing](#contributing)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## What it does

FloBlur puts a single soft scrim over your desktop and cuts a clean, sharp hole
around the window you are actually working in. Everything behind it — other
windows, the desktop, other apps — fades into blur and dim. Move to another
window and the sharp region moves with it.

It is a **menu-bar app**: no Dock icon, no window in the app switcher. It turns
on with a hotkey, stays out of the way, and gets out of its own way.

Because it works from window *metadata* instead of screen *capture*, FloBlur
never asks for Screen Recording or Accessibility access — nothing to approve,
nothing revoked by accident when you change a password.

## Features

### The effect

- **Blur / Dim / Both** background effect, per display.
- **Live intensity sliders** (0–100 %) with a live preview.
- **Dim colours**: neutral, warm, or a custom hex wash.
- **Sharp holes** for pinned windows — pin an app and it stays crisp on top of
  the scrim while everything else fades.
- **Hover peek** — rest the cursor on a fading window to bring it back, and it
  re-fades when you move away (delay adjustable from 0.15 s to 1.5 s).
- **Warm with Night Shift** — while it's on, the dim wash turns warm whenever
  system Night Shift is active (via CoreBrightness).

### Presets & automation

- **Four built-in presets** — Coding, Reading, Presenting, Deep Focus — each
  with its own style, intensities, and app lists.
- **Custom presets** with their own hotkeys, exclusions, and always-sharp apps.
- **Per-preset hotkeys** — press one to apply that preset and turn the effect on.
- **Automatic preset by app** — give Xcode the Coding preset and Mail the
  Reading preset; switching apps switches the look.
- **Pomodoro focus sessions** — focus / break / long-break lengths, rounds
  before a long break, which preset to apply while focusing, optional
  auto-continue, plus pause, resume and skip.
- **Working hours** — turn the effect on automatically between chosen times on
  chosen weekdays, with a preset of your choice.
- **URL scheme** (`floblur://`) so Shortcuts, Focus modes, or scripts can drive
  the effect.

### Behaviour & compatibility

- Optional: keep **tiled and Split View** windows sharp.
- **Pause the effect** — put an app on the *don't fade* list and the whole
  desktop stops fading while that app is frontmost.
- Optional: fade the **active app's other windows** too (on by default — turn it
  off to keep the rest of your app's windows crisp).
- Optional: **turn off in full-screen apps**.
- Optional: **turn off while screen sharing or presenting**.
- Optional: **fade the desktop** when nothing is focused.
- **Fade only the display** that holds the active window, or every display.
- **Per-display overrides** — never fade a specific monitor, or give it its own
  blur/dim levels, independent of the global sliders.
- **Pause / always-sharp / auto-preset** app lists, keyed by bundle ID.
- **Toggle HUD** so you can see what changed without opening anything.
- **Cursor-shake toggle** (off by default) with a sensitivity slider.
- **Single instance enforced** — a second copy retires itself instead of
  fighting over the same switch.

### Behaviours worth knowing before you tune it

These are deliberate rules, not bugs:

| Situation | What FloBlur does |
|---|---|
| **Reduce Transparency** is on in macOS accessibility settings | The effect is forced to **dim**, ignoring Blur/Both — accessibility beats the slider |
| **Mission Control / Exposé** is open | With **Blur** or **Both**, the scrim fades out so you can see your spaces; **Dim** keeps dimming |
| Front app is on the *don't fade* list | The **entire** effect pauses (it's an "I'm presenting / on a call" escape hatch, not a per-app exclusion) |
| **Screen sharing** or presenting | Overlay windows are kept out of screen captures; the effect turns off if you enable that toggle |
| A window is **full-screen** | Effect off, if you enable that toggle |
| Working hours unset | Off; the default schedule, if enabled, is **Mon–Fri 09:00–18:00** |
| Focus sessions unset | **25 min focus / 5 min break / 15 min long break, 4 rounds**, Deep Focus applied while focusing |
| Custom dim colour unset | `#3A2A1A` |

### System integration

- Launch at login (via `SMAppService`).
- **In-app updates** via Sparkle, with automatic check/download toggles.
- Universal binary: Apple Silicon and Intel in one download.

## Requirements

| | |
|---|---|
| **macOS** | 14 Sonoma or later |
| **Architectures** | Apple Silicon and Intel (universal) |
| **Build toolchain** | Xcode 16+ (Swift 5.0, AppKit + SwiftUI) |
| **Dependencies** | Sparkle 2.10.0 (resolved automatically via SwiftPM) |
| **Permissions** | None — no Screen Recording, no Accessibility |

## Install

### Download a release

Grab the latest `.dmg` from the
[releases page](https://github.com/DeaDoes/FloBlur/releases/latest), then:

1. Open `FloBlur-<version>.dmg`.
2. Drag **FloBlur.app** into **Applications**.
3. On the **first launch only**, right-click FloBlur → **Open** → **Open**.

> **Why the extra step?** FloBlur is distributed with a self-signed identity, not
> an Apple Developer ID, so macOS Gatekeeper quarantines the app the first time.
> After that first open, launches and in-app updates are silent. See
> [Releases & auto-update](#releases--auto-update).

### Install from a clone

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Release build
open ~/Library/Developer/Xcode/DerivedData/FloBlur-*/Build/Products/Release/FloBlur.app
```

### Build from source

See [Build from source](#build-from-source).

## Quick start

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
open FloBlur.xcodeproj     # ⌘R to build & run
```

Or on the command line:

```sh
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Debug build
```

FloBlur runs from the **menu bar** (no Dock icon). Click the menu-bar icon to
open the popover, flip the switch, and the effect is live.

## Using FloBlur

### Menu-bar popover

The popover is the fast path — everything you need without leaving your app:

- **Preset pills** — one tap to apply a preset.
- **Style picker** — Blur / Dim / Both.
- **Live sliders** — drag blur and dim, watch the desktop change under you.
- **Per-app rows** — *Don't fade the front app* / *Keep the front app sharp*.
- **Focus session row** — start, stop, pause, resume, or skip a phase, with a
  live countdown.
- **Check for Updates…**, **Settings**, **Welcome guide**, **Quit FloBlur**.
- **Stacking warnings** — if another FloBlur or a similar defocus app is also
  running, the popover says so instead of letting you debug a black desktop.

### Settings window

| Pane | What's in it |
|---|---|
| **General** | Launch at login, update check/download toggles, cursor-shake toggle + sensitivity, global shortcut enable + combo recorder, URL-scheme cheatsheet |
| **Appearance** | Preset chips, effect style, blur/dim intensity, dim colour (neutral / warm / custom hex), warm with Night Shift, behaviour toggles, hover peek + delay, live preview card |
| **Displays** | Fade only the active display, per-display *never fade*, per-display blur/dim overrides with reset-to-global |
| **Timing** | Working hours (days, start, end, preset), focus sessions (focus / break / long break, rounds, preset while focusing, auto-continue) |
| **Apps** | Three lists: *don't fade* (excluded), *always sharp*, and *automatic preset* — all keyed by bundle ID |
| **About** | Version and build number |

### Presets

| Preset | Style | Blur | Dim |
|---|---|---|---|
| **Coding** | Both | 65 % | 30 % |
| **Reading** | Blur | 88 % | 0 % |
| **Presenting** | Dim | 0 % | 30 % |
| **Deep Focus** | Both | 85 % | 55 % |

Applying a preset restores its style, intensities, colour, and app lists in one
move. Editing an intensity afterwards clears the active preset mark, so a
hand-tuned look never lies about which preset is on. Custom presets are saved
alongside the built-ins and can each get their own hotkey.

### URL scheme (Shortcuts & Focus)

Point any Shortcuts app, Focus automation, Raycast, Alfred, or shell script at
these:

| URL | Action |
|---|---|
| `floblur://toggle` | Toggle the effect |
| `floblur://on` | Turn the effect on |
| `floblur://off` | Turn the effect off |
| `floblur://settings` | Open the Settings window |
| `floblur://preset/<id>` | Apply a preset (by ID, e.g. `deep-focus`, or by name) and turn the effect on |
| `floblur://pomodoro/start` | Start a focus session |
| `floblur://pomodoro/pause` | Pause the session |
| `floblur://pomodoro/resume` | Resume the session |
| `floblur://pomodoro/skip` | Skip to the next phase |
| `floblur://pomodoro/stop` | Stop the session |

```sh
open "floblur://toggle"
open "floblur://preset/coding"
```

Wire `floblur://on` to a macOS **Focus** mode and the effect follows Work,
Study, or whatever you name it.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌥⌘B` *(default, rebindable)* | Toggle the effect |
| Per-preset hotkeys | Apply that preset and turn the effect on |

The main combo and every preset combo are recorded with the in-app recorder —
no Accessibility permission needed.

## How it works

1. **Track.** `ActiveWindowTracker` polls `CGWindowListCopyWindowInfo` and listens
   to workspace notifications for app activation, deactivation, termination,
   wake, and Space changes. Mission Control posts no such notification, so a
   dedicated fast watcher scans the Dock window list to catch it. Polling cadence
   backs off (0.1 s → 2 s → 6 s) as the machine goes idle.
2. **Anchor.** The frontmost on-screen window becomes the anchor; its rect is
   mapped into global coordinates so pinned windows can be cut as holes.
3. **Overlay.** One transparent, click-through overlay window per display sits
   directly beneath the anchor window, above everything else. It applies
   background blur via SkyLight, falls back to an `NSVisualEffectView` where the
   private call is unavailable, and adds a tinted dim layer for dim opacity.
4. **Refine.** Behaviour rules run against the snapshot: skip full-screen apps,
   skip while sharing, keep tiled windows sharp, skip a display with
   `neverFade`, or fade only the display holding the active window.
5. **Peek.** With peek on, a lightweight mouse-moved monitor reveals the window
   under a stationary cursor and re-fades it after the delay.
6. **Re-apply.** Every settings change calls `requestApply()`, which coalesces
   bursts (slider drags) per runloop so dragging never queues a hundred applies.

The result is metadata-only compositing: no pixels are read, nothing is
recorded, and no permission prompt exists to answer.

## Permissions & privacy

FloBlur asks for **no permissions at all**.

| Question | Answer |
|---|---|
| Screen Recording? | Not requested, not used |
| Accessibility? | Not requested, not used |
| Network access? | Only the Sparkle update feed (`appcast.xml`) |
| Analytics / telemetry? | None — no analytics SDK, no crash reporting, no tracking |
| What is stored? | Preferences only, in your own `UserDefaults` (`me.floblur.FloBlur`) |
| Screenshots? | Never captured, never written to disk |

The only data that leaves your Mac is the Sparkle version check against the
project's own `appcast.xml` on GitHub, which is opt-out in
**Settings → General → Updates**.

To erase every stored preference:

```sh
defaults delete me.floblur.FloBlur
```

## Private APIs

Some of the best-looking macOS effects have no public API. FloBlur uses two
private interfaces, loaded dynamically with a safe fallback so a future macOS
release degrades instead of crashing:

| Interface | Used for | If it disappears |
|---|---|---|
| `CGSMainConnectionID` + `CGSSetWindowBackgroundBlurRadius` / `SLSSetWindowBackgroundBlurRadius` in `SkyLight.framework` | Real background blur on overlay windows | Falls back to `NSVisualEffectView` blur, then dim-only |
| `CBBlueLightClient` in `CoreBrightness.framework` | Detecting whether Night Shift is active, to warm the wash | The wash simply stops auto-warming; your chosen tint is untouched |

Both are resolved with `dlopen`/`dlsym` at first use and **fail closed** — if a
symbol is missing, FloBlur degrades and says so. Run the diagnostic to check
what your machine supports:

```sh
swiftc -o /tmp/floblur_diag Tools/diagnose-apis.swift -framework AppKit && /tmp/floblur_diag
```

It prints which legs of the effect are alive on your system and changes nothing.

Because of these private interfaces, behaviour can change between macOS
releases without notice. If an update breaks the effect, run the diagnostic —
the output tells you which leg died.

## Project layout

```
FloBlur/
├── FloBlur.xcodeproj/            # Xcode project (shared scheme: FloBlur)
├── FloBlur/
│   ├── FloBlurApp.swift          # App entry point
│   ├── AppDelegate.swift         # Wiring, hotkeys, URL scheme, single instance
│   ├── Info.plist                # Bundle id, URL scheme, Sparkle feed + key
│   ├── AppIcon.icns
│   ├── Engine/
│   │   ├── ActiveWindowTracker.swift  # Window discovery + idle-aware cadence
│   │   ├── OverlayController.swift    # Per-display overlay orchestration
│   │   ├── OverlayWindow.swift        # Transparent click-through overlay window
│   │   ├── SkyLight.swift             # Private background-blur loader
│   │   ├── FocusScheduler.swift       # Working hours + pomodoro sessions
│   │   ├── FocusState.swift           # Snapshot types, pause reasons
│   │   ├── HotKeyManager.swift        # Carbon global hotkeys
│   │   ├── NightShift.swift           # CoreBrightness Night Shift monitor
│   │   ├── ShakeDetector.swift        # Cursor-shake toggle
│   │   └── ToggleHUD.swift            # On-screen change feedback
│   ├── Models/
│   │   ├── Settings.swift        # UserDefaults-backed settings store
│   │   ├── Presets.swift         # Built-in + custom presets
│   │   └── ColorHex.swift        # Hex colour parsing
│   └── Views/
│       ├── MenuPopoverView.swift # Menu-bar popover
│       ├── SettingsView.swift    # Settings window (General/Appearance/Displays/Timing/Apps/About)
│       ├── PresetManagerView.swift
│       ├── ShortcutRecorderView.swift
│       └── OnboardingView.swift  # First-launch welcome guide
├── Tools/
│   ├── build-dmg.sh              # Signed universal build → styled DMG
│   ├── render-dmg-background.swift
│   ├── update-appcast.py         # Rewrite appcast.xml after a release
│   ├── diagnose-apis.swift       # Private-API diagnostic (not in the app target)
│   └── dmg-background.png
├── .github/workflows/            # CI build check + release pipeline
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
└── LICENSE
```

## Build from source

**Requirements:** macOS 14+, Xcode 16+, an Apple Silicon or Intel Mac.

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
```

Build and run from Xcode:

```sh
open FloBlur.xcodeproj       # select the FloBlur scheme, press ⌘R
```

Build from the command line:

```sh
# Debug (active arch)
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Debug build

# Release, universal, ad-hoc signed
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

The app is produced at:

```
~/Library/Developer/Xcode/DerivedData/FloBlur-*/Build/Products/{Debug,Release}/FloBlur.app
```

SwiftPM resolves Sparkle 2.10.0 automatically on first build; there is no
package to install by hand.

To produce a distributable, styled DMG locally:

```sh
SIGN_IDENTITY="FloBlur" ./Tools/build-dmg.sh 1.0
# -> dist/FloBlur-1.0.dmg
```

## Tools

| Tool | Purpose |
|---|---|
| `Tools/build-dmg.sh` | Universal Release build, codesign, styled DMG with background art, verify + cleanup. Honours `SIGN_IDENTITY`. |
| `Tools/render-dmg-background.swift` | Regenerates `Tools/dmg-background.png`, the DMG window artwork. |
| `Tools/update-appcast.py` | Rewrites `appcast.xml` with a new release item (version, length, EdDSA signature). |
| `Tools/diagnose-apis.swift` | Standalone diagnostic that reports which private APIs are available. Not part of the app target. |

## Releases & auto-update

Releases are tag-driven and automated:

```sh
# 1. bump MARKETING_VERSION in FloBlur.xcodeproj to match the tag, commit, push
# 2. tag — the workflow fails fast if the tag and the project version disagree
git tag v1.1
git push origin v1.1
```

`.github/workflows/release.yml` then produces:

- `FloBlur-<ver>.dmg` — for people (drag into Applications).
- `FloBlur-<ver>.zip` — for Sparkle (progress bar, install-and-relaunch).
- an updated `appcast.xml` committed back to `main`, so in-app updates light up.

**On signing:** releases use a self-signed identity from repository secrets.
There is deliberately **no notarization step** — that requires paid Apple
Developer Program membership. Consequences:

- First launch on another Mac: right-click → **Open** (once).
- In-app updates are still verified by **Sparkle EdDSA signatures**, which need
  no Apple involvement. An update with a bad signature is refused.
- **Hardened runtime:** the Xcode project enables it (`ENABLE_HARDENED_RUNTIME`),
  but `Tools/build-dmg.sh` deliberately re-signs the built app *without*
  `--options runtime`, so the shipped binary is not hardened. With a Team-less
  self-signed identity, library validation would otherwise reject the re-signed
  `Sparkle.framework` at launch and the app would crash-loop on other Macs.
  Re-add the flag only together with a real Developer ID signature.

Required repository secrets:

| Secret | Contents |
|---|---|
| `MACOS_CERT_P12` | base64 of the exported code-signing `.p12` |
| `MACOS_CERT_PASSWORD` | the `.p12` export password |
| `MACOS_CERT_NAME` | signing identity name (e.g. `FloBlur`) |
| `SPARKLE_ED_KEY` | Sparkle Ed25519 private key (keychain item, account `ed25519`) |

## Contributing

Pull requests are welcome — see **[CONTRIBUTING.md](CONTRIBUTING.md)** for the
full workflow: how to build, code style, commit conventions, and what a good
PR looks like here. Short version:

1. Open an issue first for anything larger than a bug fix, so we agree on the
   approach before you write the code.
2. Branch off `main`, one topic per branch.
3. Make sure `⌘R` runs clean and the CI build check passes.
4. Keep changes focused; unrelated cleanups belong in their own PR.

Everyone participating is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Troubleshooting

**"Nothing happens when I turn it on."**
Check that another copy isn't running. FloBlur enforces a single instance, but a
copy started outside the app (debugger, stale process) can still confuse things —
quit any extra FloBlur in Activity Monitor. The popover also warns when another
FloBlur or a similar defocus app is detected on screen.

**"The background is black / solid instead of blurred."**
Two effects stacking on the same windows produce a black scrim. Quit the other
app. If only blur is missing and dim still works, the private blur symbol is
probably gone on your macOS version — run the diagnostic:

```sh
swiftc -o /tmp/floblur_diag Tools/diagnose-apis.swift -framework AppKit && /tmp/floblur_diag
```

**"macOS says the app is damaged or can't be opened."**
Expected on first launch for an unsigned app. Right-click the app → **Open** →
**Open**. To reset quarantine:

```sh
xattr -dr com.apple.quarantine /Applications/FloBlur.app
```

**"The effect flickers / fights the app I switched to."**
Try **Appearance → Behaviour → Keep tiled and Split View windows sharp**, and
**Turn off in full-screen apps**. If another defocus app is installed, run only
one at a time.

**"The app doesn't show up in the Dock."**
Correct — FloBlur is a menu-bar (`LSUIElement`) app. Look next to the clock; you
can also open it with `open -a FloBlur` or `open "floblur://settings"`.

**"Settings or shortcuts aren't sticking."**
FloBlur registers Carbon hotkeys; some apps (and some remote-desktop software)
steal combinations. Record a different combo, and check for a second copy of
FloBlur running.

**"I want everything back to defaults."**

```sh
defaults delete me.floblur.FloBlur
```

then quit and relaunch FloBlur. Note this also clears the "onboarding finished"
flag, so the welcome guide will show itself again on the next launch — a handy
way to replay it deliberately.

## FAQ

**Does it need Screen Recording or Accessibility?**
No. FloBlur reads window *metadata* and composites a scrim; it never reads
pixels. Neither permission is requested.

**Will it work while screen sharing?**
There is a toggle to turn the effect off while sharing or presenting
(**Appearance → Behaviour**), because softening your whole desktop makes shared
screens harder to read — your call.

**Does it slow things down?**
Overlays are composited by the window server and hidden when not needed.
Tracking polling backs off while you are idle. You will not notice it unless you
look for it.

**Can I have a different look on two monitors?**
Yes — per-display blur/dim overrides and a *never fade* switch, in
**Settings → Displays**.

**Why is there no Dock icon?**
It is a focus tool, not a workspace app. It should be reachable by one hotkey and
otherwise invisible.

**Is this related to the paid app it resembles?**
No. FloBlur is an independent, MIT-licensed open-source project. It simply
implements the same well-known idea: soften everything except the window you are
using.

**Can I use it commercially / fork it?**
Yes — MIT. See [LICENSE](LICENSE).

## License

Released under the **MIT License**. See [LICENSE](LICENSE) for the full text.

```
Copyright (c) 2026 DeaDoes
```

## Acknowledgements

- **[Sparkle](https://github.com/sparkle-project/Sparkle)** — the update
  framework, with EdDSA update signing.
- **The macOS community** — for the free, open-source alternatives that made
  this worth building in the open.
- **Everyone who files an issue** — especially the ones that arrive with a
  screenshot and a `diagnose-apis` dump.

Contributions of every size are credited in [CHANGELOG.md](CHANGELOG.md) and the
commit history.
