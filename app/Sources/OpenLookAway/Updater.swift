import AppKit
import Observation

/// Checks GitHub Releases and updates by re-running the install script,
/// which is unsigned-friendly (curl downloads aren't quarantined by Gatekeeper).
@MainActor @Observable
final class Updater {
    static let shared = Updater()
    static let repo = "yoelgal/openlookaway"

    private(set) var available: String?
    private(set) var installing = false

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    private init() {
        Task { await check() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { await Updater.shared.check() }
        }
    }

    @discardableResult
    func check() async -> Bool {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return false }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        available = latest.compare(current, options: .numeric) == .orderedDescending ? latest : nil
        return true
    }

    func checkInteractively() {
        Task {
            let ok = await check()
            if available != nil { return install() }
            let alert = NSAlert()
            alert.messageText = ok ? "You're up to date" : "Couldn't check for updates"
            alert.informativeText = ok ? "OpenLookAway \(current) is the latest version." : "Check your internet connection and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    func install() {
        installing = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "curl -fsSL https://raw.githubusercontent.com/\(Self.repo)/main/site/install.sh | bash"]
        p.terminationHandler = { proc in
            // The script quits and relaunches us on success; we only get here if it failed.
            Task { @MainActor in
                Updater.shared.installing = false
                if proc.terminationStatus != 0 { NSWorkspace.shared.open(URL(string: "https://lookaway.yoelgal.com")!) }
            }
        }
        try? p.run()
    }
}
