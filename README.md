<div align="center">

# FloBlur

**One clear window.**

FloBlur keeps the window you're working in razor sharp and gently softens
everything behind it — blur it, dim it, or both. Your windows never move,
nothing gets hidden. Distraction just stops shouting.

[Download](https://github.com/DeaDoes/FloBlur/releases/latest) · [Features](#features) · [Install](#install) · [Shortcuts](#shortcuts--automation) · [Build](#build-from-source) · [FAQ](#faq)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon + Intel](https://img.shields.io/badge/arch-arm64_%2B_x86__64-lightgrey)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Updates: Sparkle](https://img.shields.io/badge/updates-Sparkle-orange)

</div>

---

## The idea

Every Mac user knows the feeling: twelve windows open, the one that matters
drowning in the ones that don't. Virtual desktops help you organize.
FloBlur helps you *see* — it treats attention like a spotlight. Whatever
you're touching stays crisp; the rest melts into a soft backdrop. No new
workflow to learn, no windows to manage. Just less in the way.

## Features

| | |
|---|---|
| **The effect** | Blur, dim, or both — tuned per display with live sliders, previewed as you drag |
| **Presets** | Coding, Reading, Presenting, Deep Focus out of the box; save your own looks, give each a hotkey, pin each to the apps it belongs to |
| **Menu bar home** | Presets, sliders, per-app actions, sessions, updates — everything lives in one quiet popover. No Dock icon |
| **Focus sessions** | Pomodoro rounds with pause, skip, short and long breaks, and a live countdown ticking right in the menu bar |
| **Working hours** | The effect follows your day — on during work hours (overnight shifts included), off outside them, each with its own look |
| **Per-app rules** | Pause the effect for specific apps, keep favorites always sharp, or auto-apply a preset when an app comes forward |
| **Little things** | Global shortcut (⌥⌘B), toggle-by-shaking the cursor, hover-to-peek at faded windows, a wash that warms with Night Shift, `floblur://` URLs for Shortcuts |

And the part you'll never notice: **it asks for nothing.** No Screen
Recording, no Accessibility access, no account. It reads window positions,
never window contents.

---

## Install

1. Grab **`FloBlur-1.0.dmg`** from [the latest release](https://github.com/DeaDoes/FloBlur/releases/latest).
2. Open it, drag **FloBlur** into **Applications**.
3. **Right-click → Open** on first launch (self-signed build — one approval, then never again).
4. Flip the switch in the menu-bar popover. Done.

> Updates arrive inside the app: release notes, a progress bar, and an
> install-and-relaunch. You never touch a DMG twice.

---

## Shortcuts & automation

| Action | How |
|---|---|
| Toggle the effect | ⌥⌘B (remappable in Settings) |
| Toggle by shaking | Settings → Cursor shake |
| Sessions | Menu bar, Settings → Timing, or Shortcuts |
| URL schemes | `floblur://toggle` · `floblur://on` · `floblur://off` · `floblur://preset/coding` · `floblur://pomodoro/start` · `/pause` · `/resume` · `/skip` · `/stop` |

Shortcuts automations can call those URLs — e.g. switch the effect on with a
Focus mode and off when it ends.

---

## Build from source

Requirements: macOS 14+, Xcode 16+.

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
open FloBlur.xcodeproj   # press ⌘R to build & run
```

Headless:

```sh
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Debug build
```

Release DMG (signed, universal, styled installer window):

```sh
./Tools/build-dmg.sh 1.0
```

Tagging `vX.Y` runs the same pipeline on CI and publishes the release.

**Repo map**

| Path | What lives there |
|---|---|
| `FloBlur/Engine/` | Overlay, window tracker, session scheduler, hotkeys, shake, updater glue |
| `FloBlur/Models/` | Settings store, presets |
| `FloBlur/Views/` | Popover, settings panes, onboarding, shortcut recorder |
| `Tools/` | `build-dmg.sh`, DMG art + generator, API diagnostics |
| `appcast.xml` | Sparkle update feed (regenerated per release by CI) |

---

## FAQ

**It asks for nothing on launch — is that right?**
Yes. No permissions, no account, no Dock icon. If macOS ever prompts you for
anything, that prompt is the news — please file an issue.

**"Unidentified developer" on first open?**
Expected for a self-signed build: right-click → Open once (or Privacy →
Open Anyway). A paid Developer ID would remove this; it's on the roadmap,
not in the budget.

**Effect disappeared in full screen / while sharing?**
That's the Behaviour toggles doing their job — Settings → Appearance.

**Background goes black instead of blurred?**
Two blur effects stacked on each other turn the backdrop black. If you're
running another copy of FloBlur (or a similar tool), quit one — the popover
tells you when it spots a conflict.

---

## License

MIT — see [LICENSE](LICENSE).
