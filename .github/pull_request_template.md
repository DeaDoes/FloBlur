<!--
Thanks for the PR. Keep it focused — unrelated refactors and formatting belong
in their own branch, because this codebase's window-layer behaviour is hard to
review when it's buried in noise.
-->

## What this changes

<!-- One or two sentences. Link the issue it closes: Closes #123 -->

## Why

<!-- The cause, not the diff. What breaks without this? -->

## How it was verified

<!-- Required. Be concrete — this is a visual, window-layer app. -->

- macOS version:
- Mac model / displays:
- Tiling software, Stage Manager, Mission Control / Exposé in use:
- Other focus or defocus apps running:

Steps:

1.
2.
3.

<!-- If private APIs are touched, paste the diagnostic output:
     swiftc -o /tmp/floblur_diag Tools/diagnose-apis.swift -framework AppKit && /tmp/floblur_diag -->

## Checklist

- [ ] Built from clean DerivedData and ran it (`⌘R`).
- [ ] CI build check passes.
- [ ] Matches the surrounding style; comments explain *why*, not *what*.
- [ ] No new permission requests (no Screen Recording, no Accessibility).
- [ ] No new dependency. (Sparkle is the only one, deliberately.)
- [ ] If a new private API is used: it fails closed, has a fallback, and
      `Tools/diagnose-apis.swift` was updated in this PR.
- [ ] If settings changed: stable `UserDefaults` key, registered default,
      defensive decoding for existing users, and a control in the right pane.
- [ ] Docs updated (`README.md` / `CHANGELOG.md`) where behaviour changed.

## Screenshots

<!-- Before / after, or a short recording. For anything visual, this is most of
     the review. -->
