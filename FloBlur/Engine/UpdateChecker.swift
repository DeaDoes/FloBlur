import Foundation
import AppKit

/// Minimal update check against GitHub releases (stands in for Sparkle until
/// the release feed is configured). Disabled when no repo is set.
enum UpdateChecker {
    /// Set to "owner/repo" once the open-source home exists.
    static let repository = ""

    static var isConfigured: Bool { !repository.isEmpty }

    static func check() {
        guard isConfigured,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else { return }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            guard tag.trimmingCharacters(in: .whitespaces) != current,
                  tag.trimmingCharacters(in: .whitespaces) != "v\(current)"
            else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "An update is available (\(tag))."
                alert.informativeText = "Download it from the GitHub releases page."
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn,
                   let page = URL(string: "https://github.com/\(repository)/releases/latest") {
                    NSWorkspace.shared.open(page)
                }
            }
        }.resume()
    }
}
