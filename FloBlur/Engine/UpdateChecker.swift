import Foundation
import AppKit

/// Update check against GitHub releases. Configured for the public home —
/// the General toggles and the delayed launch check are live.
/// On a newer tag the alert deep-links the release's `.dmg` asset itself
/// (falls back to the releases page when no DMG is attached).
enum UpdateChecker {
    static let repository = "DeaDoes/FloBlur"

    static var isConfigured: Bool { !repository.isEmpty }

    /// Pure decision: given the current version and a decoded `/releases/latest`
    /// payload, which (tag, downloadURL) should be offered, if any.
    /// Separated out so release-day logic is unit-testable without network.
    static func offer(current: String, payload: [String: Any]) -> (tag: String, url: URL)? {
        guard let tag = payload["tag_name"] as? String,
              isNewer(tag: tag, than: current)
        else { return nil }
        let assets = payload["assets"] as? [[String: Any]] ?? []
        if let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
           let raw = dmg["browser_download_url"] as? String,
           let url = URL(string: raw) {
            return (tag, url)
        }
        guard let page = URL(string: "https://github.com/\(repository)/releases/latest") else { return nil }
        return (tag, page)
    }

    /// Tag comparison tolerant of a leading `v` on either side.
    static func isNewer(tag: String, than current: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespaces)
        let c = current.trimmingCharacters(in: .whitespaces)
        guard t != c, t != "v\(c)", "v\(t)" != c else { return false }
        return true
    }

    static func check(autoDownload: Bool = false) {
        guard isConfigured,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let offer = offer(current: current, payload: json)
            else { return }
            if autoDownload, offer.url.pathExtension.lowercased() == "dmg" {
                downloadInBackground(offer: offer)
            } else {
                DispatchQueue.main.async { showOfferAlert(offer: offer) }
            }
        }.resume()
    }

    /// Silent fetch into ~/Downloads, then a reveal prompt. Never mounts or
    /// replaces anything on its own — install stays a user drag-and-drop.
    private static func downloadInBackground(offer: (tag: String, url: URL)) {
        URLSession.shared.downloadTask(with: offer.url) { location, _, error in
            guard error == nil, let location else { return }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            let dest = uniqueDestination(offeredName: offer.url.lastPathComponent, in: downloads)
            guard let dest, (try? FileManager.default.moveItem(at: location, to: dest)) != nil else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "FloBlur \(offer.tag) downloaded."
                alert.informativeText = "Open \(dest.lastPathComponent) in Downloads and drag FloBlur into Applications to replace your copy."
                alert.addButton(withTitle: "Reveal in Finder")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            }
        }.resume()
    }

    /// Non-colliding destination: `Name.dmg`, `Name 2.dmg`, … Pure helper,
    /// unit-tested with a temp dir.
    static func uniqueDestination(offeredName: String, in dir: URL?) -> URL? {
        guard let dir else { return nil }
        let stem = (offeredName as NSString).deletingPathExtension
        let ext = (offeredName as NSString).pathExtension
        var candidate = dir.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    private static func showOfferAlert(offer: (tag: String, url: URL)) {
        let alert = NSAlert()
        alert.messageText = "An update is available (\(offer.tag))."
        alert.informativeText = "Download FloBlur \(offer.tag) and replace the copy in Applications."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(offer.url)
        }
    }
}
