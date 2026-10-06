# Security Policy

FloBlur is a local, menu-bar macOS app. It has no accounts, no server, no
database, and it requests **no system permissions**. That makes the threat model
small — but not empty, so here's what we consider in scope and how to report it.

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x (current release) | ✅ |
| < 1.0 | ❌ |
| Unreleased `main` | Best effort — fix in `main`, ship in the next release |

## Reporting a vulnerability

**Please do not open a public issue for a security report.**

Use GitHub's private reporting so the details stay confidential until a fix
exists:

**Repository → Security → Report a vulnerability**
(or <https://github.com/DeaDoes/FloBlur/security/advisories/new>)

If that flow is unavailable, open a public issue titled `[security] contact me`
containing no technical detail, and we'll start a private channel with you.

Please include, as far as you can:

- What you found, and what an attacker gains from it.
- Reproduction steps, ideally with a minimal `.swift` or `.sh` snippet.
- Your macOS version and Mac model.
- Whether the issue requires the user to already run a malicious build.

### What to expect

- Acknowledgement within a few days.
- An assessment (severity, fix plan, or "not reproducible") as soon as we can.
- Credit in the release notes, unless you'd rather stay anonymous.
- A disclosure timeline agreed with you before anything is published.

Please give the maintainer a reasonable window to ship a fix before disclosing
publicly.

## In scope

- **The update channel.** FloBlur auto-updates from `appcast.xml` on GitHub
  over HTTPS, and each update archive is verified with a Sparkle EdDSA
  signature before installation. Anything that could let an attacker deliver or
  substitute an update — signature bypass, feed hijack, downgrade to a
  vulnerable build — is a serious report.
- **Code execution or privilege escalation** through crafted inputs: bundle IDs
  in the app lists, window metadata read from other apps, `floblur://` URL
  arguments, or `UserDefaults` values, including values written by another
  process.
- **Privacy violations.** Any capture, retention, or transmission of screen
  content, window titles, keystrokes, or browsing activity. FloBlur reads window
  *geometry and metadata* to decide where to cut a hole and never reads pixels.
  A change that made it capture or log content would be a regression, not a
  feature.
- **Network activity beyond the update check.** There should be none. Unexpected
  egress is a report.
- **Local privilege escalation or sandbox/permission-boundary escapes** reached
  from inside the app.
- **Release supply chain**: the signing keychain, the self-signed identity, or
  the Sparkle Ed25519 key being exposed or usable by someone else.

## Out of scope

These are design properties, not vulnerabilities:

- **Use of private macOS APIs** (`SkyLight`,
  `CGSSetWindowBackgroundBlurRadius`/`SLSSetWindowBackgroundBlurRadius`,
  `CoreBrightness`'s `CBBlueLightClient`). This is the mechanism the effect is
  built on. It may break on a future macOS; when it does, FloBlur degrades to
  `NSVisualEffectView` blur or dim-only. Report a *crash, data access, or
  unexpected code execution* caused by these APIs — not their existence.
- **Visual glitches**: a black background, a misplaced sharp region, a window
  that doesn't fade, an overlay on the wrong display, or interference with
  another focus/defocus app. These are bugs — file them as **bugs**, not
  security reports, and you'll get a faster response.
- **Gatekeeper warnings and "app is damaged" messages** on first launch. FloBlur
  is distributed self-signed and intentionally not notarized, because
  notarization requires paid Apple Developer Program membership.
- **Missing Accessibility permission**, which FloBlur never requests and does not
  need.
- **Denial of service against the running app** (e.g. spawning thousands of
  FloBlur instances) that requires local code execution — at that point the
  attacker already owns the machine.
- Reports against **macOS itself**, Apple's update verification, or GitHub's
  infrastructure.
- Reports generated solely by an automated scanner with no demonstrated impact.

## Security design notes

For reviewers and reporters, the properties FloBlur tries to hold:

- **Zero permission requests.** No `NSScreenCaptureUsageDescription`, no
  Accessibility. Nothing to escalate from.
- **No screen capture.** Window geometry comes from
  `CGWindowListCopyWindowInfo`, which needs no permission; pixels are never read.
- **No telemetry.** No analytics or crash-reporting SDK is linked.
- **Fail-closed private API loading.** Symbols are resolved via
  `dlopen`/`dlsym`; a missing symbol degrades the effect rather than executing
  anything unexpected.
- **Local-only state.** Preferences live in your own `UserDefaults` domain,
  `me.floblur.FloBlur`. Reset with:
  ```sh
  defaults delete me.floblur.FloBlur
  ```
- **Egress is limited to the update feed**, and is opt-out in
  **Settings → General → Updates**.
- **Single instance enforced**, so two copies can't fight over the same switch
  (or window layer).

If you believe one of these properties no longer holds, that is exactly the kind
of report we want.

## License

FloBlur is MIT-licensed. Auditing and patching the source is explicitly welcome.
See [LICENSE](LICENSE) and [CONTRIBUTING.md](CONTRIBUTING.md).
