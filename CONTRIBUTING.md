# Contributing to FloBlur

Thanks for taking a look. FloBlur is a small native macOS app with a big surface
area — overlays, window tracking, private APIs, automation — so contributions of
every size are genuinely useful, from a typo fix to a new preset engine.

This document is the contract. Read it before opening a PR.

**By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).**

## Table of contents

- [Ways to help](#ways-to-help)
- [Before you write code](#before-you-write-code)
- [Setting up](#setting-up)
- [Making a change](#making-a-change)
- [Code style](#code-style)
- [Commit messages](#commit-messages)
- [Tests and CI](#tests-and-ci)
- [Working with private APIs](#working-with-private-apis)
- [Adding settings or presets](#adding-settings-or-presets)
- [Releasing](#releasing)
- [Reporting bugs well](#reporting-bugs-well)
- [PR review](#pr-review)

## Ways to help

Not everything needs to be code.

- **Reproduce and confirm a bug.** A "yes, I see this too on macOS 15.3" on an
  open issue is genuinely valuable here, because window-layer bugs are
  environment-specific.
- **Improve the docs.** This README, in-app copy, or comments that explain a
  non-obvious ordering constraint.
- **Test on hardware we don't have.** Intel Macs, multiple displays, mixed
  refresh rates, exotic window managers, tiling setups (yabai, Amethyst,
  Rectangle), Stage Manager, Mission Control, Exposé.
- **Report a regression** with a `Tools/diagnose-apis.swift` dump attached.
- **Translate** the in-app strings if you speak another language.

## Before you write code

**Open an issue first for anything larger than a one-line fix.** Especially for
changes that touch `Engine/OverlayController.swift`, `Engine/OverlayWindow.swift`,
or anything private-API related. A short discussion up front saves everyone a
rejected PR.

Things worth discussing first:

- New private API usage (see [Working with private APIs](#working-with-private-apis)).
- Anything that changes window stacking, ordering, or transparency — these are
  where regressions hide.
- New persisted settings (see [Adding settings or presets](#adding-settings-or-presets)).
- New dependencies. The project deliberately has exactly one (Sparkle).

**Bug fixes don't need an issue first** — just make the PR and include how you
verified it.

## Setting up

Requirements:

- macOS 14 Sonoma or later
- Xcode 16 or later (Swift 5.0)
- An Apple Silicon or Intel Mac

```sh
git clone https://github.com/DeaDoes/FloBlur.git
cd FloBlur
open FloBlur.xcodeproj        # scheme "FloBlur", press ⌘R
```

Or from the command line:

```sh
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Debug build
```

First build resolves Sparkle 2.10.0 via SwiftPM. There is nothing else to
install.

FloBlur runs from the menu bar with no Dock icon. If you do not see it after
launching, check for an existing copy:

```sh
pgrep -fl FloBlur
```

## Making a change

1. **Branch off `main`.** One topic per branch.
   ```sh
   git checkout -b fix/peek-after-mission-control
   ```
2. **Make the smallest change that fixes the thing.** Unrelated refactors,
   renames, and formatting belong in their own PR — they make review impossible.
3. **Match the surrounding code.** File layout, comment density, and naming are
   already consistent; follow them rather than importing a new style.
4. **Test on your machine**, and say in the PR how: which macOS, one display or
   many, tiling software or not.
5. **Rebuild from clean** before you push. Derived-data staleness causes bugs that
   look like code bugs.
   ```sh
   rm -rf ~/Library/Developer/Xcode/DerivedData/FloBlur-*
   ```

### Things that will bite you

The codebase carries comments about these because they have already cost time:

- **Settings are `@Published` with `didSet` writes to `UserDefaults`.** Mutating a
  published property from a non-main thread is a bug.
- **`AppDelegate` deliberately avoids explicit `syncAllHotKeys()` at launch** —
  the `@Published` sinks fire on subscribe and cover initial registration. Adding
  a manual call causes double registration.
- **`OverlayWindow`s are ordered relative to a moving anchor.** Do not reorder
  `OverlayController`'s window setup without testing multi-display behaviour.
- **The settings window has zero toolbar owners on purpose.** No
  `NavigationSplitView`, no toolbar modifiers — every attempt to reintroduce them
  re-injected a floating header. Read the comment in `SettingsView` before
  touching that layout.
- **Release builds intentionally skip hardened runtime** (`--options runtime`)
  so a self-signed Sparkle framework doesn't fail library validation and
  crash-loop. Don't "fix" that in `Tools/build-dmg.sh`.

## Code style

There is no SwiftLint config in this repo, and there is no plan to add one, so
match the file you're editing:

- 4-space indentation, standard Xcode formatting.
- `// MARK: -` section headers in files longer than ~150 lines.
- **Comments explain *why*, not *what*.** The existing comments are dense because
  the code is genuinely surprising in places. A comment that restates the next
  line is noise; a comment recording a failed alternative, a macOS quirk, or an
  ordering constraint is gold. Keep the second kind.
- Private types and helpers stay `private` unless there's a reason not to.
- Prefer the existing vocabulary: `focus` (not "session" or "mode"), `sharp`
  (not "focused" or "pinned") for windows that stay crisp, `overlay` for the
  scrim window, `preset` for a named look.

## Commit messages

Short, imperative, and specific:

```
fix: keep pinned windows sharp after a Space switch
feat: per-preset hotkeys in the popover
fix: migrate NSEvent modifier values saved by 1.0.0
docs: document the release signing model
refactor: split overlay window creation from screen mapping
```

Types: `feat`, `fix`, `refactor`, `docs`, `perf`, `test`, `build`, `chore`.

A good body explains **the cause**, not the diff — the diff is already there:

> `CGWindowListCopyWindowInfo` returns global coords while the overlay window is
> in screen space. After a display reconfiguration the cached mapping was stale,
> so pinned windows were cut in the wrong place. `noteEnvironmentChanged()` now
> invalidates the cache before the next apply.

## Tests and CI

There is no unit-test target today; the app is AppKit-window-driven and hard to
exercise headlessly. CI therefore checks the thing that actually breaks most
often: **does it still build?**

- `.github/workflows/ci.yml` builds the `FloBlur` scheme on `macos-15`.
- Your PR must pass it. If CI fails, the failure output is in the Actions tab of
  the PR.

If you add a test target, wire it into the same workflow. Tests that need a real
window server should be opt-in rather than silently skipped.

## Working with private APIs

FloBlur resolves private interfaces with `dlopen`/`dlsym` at first use and
**fails closed**, so a missing symbol degrades instead of crashing. Preserve
that property in any new private-API use:

- Resolve lazily and cache the result; never assume the symbol exists.
- Provide a fallback that still looks acceptable.
- Log or surface the degraded state so users are not left guessing.
- Extend `Tools/diagnose-apis.swift` in the same PR, so the diagnostic stays a
  truthful picture of what the app depends on.

```sh
swiftc -o /tmp/floblur_diag Tools/diagnose-apis.swift -framework AppKit && /tmp/floblur_diag
```

Never add a usage-description key or permission request to make a private API
"work" — the whole design point is that FloBlur needs zero permissions.

## Adding settings or presets

Settings are persisted as JSON-encoded strings or scalars in `UserDefaults`,
with keys declared in `FloBlurSettings.Keys`.

When you add one:

1. Add the `@Published` property with its `didSet` `UserDefaults` write.
2. Add a `Keys` constant. Keep the key string stable forever — users' stored
   preferences depend on it.
3. Register a default in `init` so a fresh install behaves sensibly.
4. Decode defensively for new optional fields (see `DisplayOverride`'s custom
   `init(from:)`), so existing users aren't broken by the addition.
5. Add the control to the right settings pane, with a sentence of explanation
   where the behaviour isn't obvious.

Presets live in `Models/Presets.swift`. A preset stores style, blur/dim
intensities, dim tint, and its two app lists. Built-ins are `static let`
constants and are treated as immutable in the UI.

Note the existing behaviour: any manual intensity edit clears
`activePresetID`. Keep that rule, or users will see a "Coding" badge on a look
they hand-tuned.

## Releases

Releases are the maintainer's job, and they are automated. If you're asked to
help with a release:

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` if the build changed)
   in `FloBlur.xcodeproj` **before** tagging.
2. Commit and push that change to `main`.
3. Tag with a `v` prefix, matching the project version exactly:
   ```sh
   git tag v1.1 && git push origin v1.1
   ```
4. `.github/workflows/release.yml` does the rest: universal signed build, styled
   DMG, Sparkle zip + EdDSA signature, GitHub Release, and an `appcast.xml`
   commit back to `main`. The workflow fails fast if the tag and the project
   version disagree, so a mistag can't ship.
5. Update `CHANGELOG.md` in the same PR as the version bump.

Never commit secrets. The signing identity, `.p12`, and Sparkle Ed25519 key live
in repository secrets only.

## Reporting bugs well

Open an issue using the **Bug report** template. The most useful things:

- macOS version (`sw_vers`), Mac model, number of displays and their arrangement.
- Tiling software, Mission Control / Stage Manager / Exposé usage.
- Whether another focus or defocus app was running at the same time.
- The `diagnose-apis` output when blur is involved.
- A screenshot or a screen recording — for a visual effect, this is most of the
  diagnosis.

## PR review

Expect review to be specific and, sometimes, slow. We care a lot about the
window-layer behaviour staying predictable, because that's the part that breaks
quietly for users on hardware the maintainer doesn't own.

A review comment is about the code, not about you. If a comment is wrong or
misses context, say so with evidence — we take correction as a favour. If a PR
goes quiet, it's almost always because the maintainer is waiting for a data point
or a discussion, not because it's unimportant.
