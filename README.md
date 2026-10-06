<div align="center">

# FloBlur

**One clear window.**

FloBlur keeps the window you're working in razor sharp and gently softens
everything behind it — blur it, dim it, or both. Your windows never move,
nothing gets hidden. Distraction just stops shouting.

[Download](https://github.com/DeaDoes/FloBlur/releases/latest) · [Features](#features) · [Install](#install) · [Shortcuts](#shortcuts) · [FAQ](#faq)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon + Intel](https://img.shields.io/badge/arch-arm64_%2B_x86__64-lightgrey)
![License: MIT](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Features

- **Blur, dim, or both** — tuned per display with live sliders
- **Presets** — Coding, Reading, Presenting, Deep Focus, plus your own with hotkeys and per-app rules
- **Menu-bar home** — everything in one quiet popover, no Dock icon
- **Focus sessions** — pomodoro rounds with pause, skip, breaks, and a live menu-bar countdown
- **Working hours** — the effect follows your day, overnight shifts included
- **Per-app rules** — pause-list, always-sharp list, auto-presets per app
- **Extras** — global shortcut (⌥⌘B), shake-to-toggle, hover peek, Night Shift wash, `floblur://` URLs

No Screen Recording or Accessibility access. No account. It reads window
positions, never window contents.

---

## Install

1. Grab **`FloBlur-1.0.dmg`** from [the latest release](https://github.com/DeaDoes/FloBlur/releases/latest).
2. Open it, drag **FloBlur** into **Applications**.
3. **Right-click → Open** on first launch (self-signed build — one approval, then never again).
4. Flip the switch in the menu-bar popover. Done.

Updates arrive inside the app — release notes, progress bar,
install-and-relaunch.

---

## Shortcuts

Toggle: ⌥⌘B (remappable) · Shake the cursor · Menu bar · `floblur://toggle` · `floblur://pomodoro/start` (plus `/pause` `/resume` `/skip` `/stop`, `/on`, `/off`, `/preset/<name>`)

---

## FAQ

**It asks for nothing on launch — is that right?**
Yes. No permissions, no account, no Dock icon.

**"Unidentified developer" on first open?**
Expected for a self-signed build: right-click → Open once.

---

## Build from source

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
open FloBlur.xcodeproj   # ⌘R to run
```

---

## License

MIT — see [LICENSE](LICENSE).
