import SwiftUI
import AppKit

/// First-launch guide: welcome → try the effect → appearance → shake → done.
/// Mirrors the original's onboarding stages. Shown until
/// `hasCompletedOnboarding` is set.
struct OnboardingView: View {
    @EnvironmentObject private var settings: FloBlurSettings
    @State private var page = 0

    var body: some View {
        VStack(spacing: 16) {
            switch page {
            case 0: welcomePage
            case 1: tryPage
            case 2: appearancePage
            case 3: shakePage
            default: finishPage
            }
            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(.link)
                }
                Spacer()
                if page < 4 {
                    Button(page == 0 ? "Continue" : "Next") { page += 1 }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 460, height: 380)
    }

    private var welcomePage: some View {
        VStack(spacing: 12) {
            AppIconImage(size: 56, cornerRadius: 13)
            Text("One clear window.")
                .font(.largeTitle)
            Text("FloBlur keeps the window you're using sharp and softens everything behind it. No new workflow — just less in the way.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var tryPage: some View {
        VStack(spacing: 12) {
            Text("Try it right now")
                .font(.title2)
            Text("Flip the switch and watch the background soften. Your windows stay exactly where they are.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Toggle("Focus mode", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .font(.headline)
                .padding(.top, 8)
            Text("Tip: press \(HotKeyCombo(keyCode: settings.shortcutKeyCode, modifiers: settings.shortcutModifiers).displayString) anytime, from any app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 12) {
            Text("Make it feel right")
                .font(.title2)
            Text("Blur, dim, or a little of both — live, behind this very window.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Picker("", selection: $settings.style) {
                Text("Blur").tag(FocusStyle.blur)
                Text("Dim").tag(FocusStyle.dim)
                Text("Both").tag(FocusStyle.both)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
            Slider(value: $settings.blurIntensity, in: 0...1) {
                Text("Blur \(Int((settings.blurIntensity * 100).rounded()))%")
            }
            Slider(value: $settings.dimIntensity, in: 0...1) {
                Text("Dim \(Int((settings.dimIntensity * 100).rounded()))%")
            }
            Spacer()
        }
    }

    private var shakePage: some View {
        VStack(spacing: 12) {
            Text("A little shake. A clear mind.")
                .font(.title2)
            Text("Give your cursor a quick shake to toggle the effect. Tune how eager it is in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Toggle("Shake cursor to toggle", isOn: $settings.shakeEnabled)
                .toggleStyle(.switch)
                .font(.headline)
                .padding(.top, 8)
            Spacer()
        }
    }

    private var finishPage: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're set.")
                .font(.largeTitle)
            Text("FloBlur lives in your menu bar. Fine-tune everything in Settings — presets, displays, timing, and apps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Start focusing") {
                settings.completeOnboarding()
                if let onboarding = NSApp.windows.first(where: { $0.title == "Welcome to FloBlur" }) {
                    onboarding.close()
                } else {
                    NSApp.keyWindow?.close()
                }
            }
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
            Spacer()
        }
    }
}
