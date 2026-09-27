import AppKit
import SwiftUI

/// `OpenLookAway --snapshots <dir>` renders every screen to PNG offscreen and quits.
/// Used for visual QA and for the website/demo assets; no Screen Recording permission needed.
@MainActor
enum Snapshots {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.async { render(to: dir); exit(0) }
    }

    private static var wallpaper: NSImage? {
        Bundle.main.url(forResource: "wall-blue", withExtension: "jpg").flatMap(NSImage.init(contentsOf:))
    }

    private static func render(to dir: URL) {
        let s = Scheduler.shared
        let wall = wallpaper.map { Image(nsImage: $0).resizable().aspectRatio(contentMode: .fill).frame(maxWidth: .infinity, maxHeight: .infinity).clipped() }

        s.stage(remaining: 17, onBreak: true)
        let blurred = Bundle.main.url(forResource: "wall-blue", withExtension: "jpg").flatMap { Backdrop.blurred($0, radius: 60) }
        save(BreakView(s: s, backdrop: blurred), size: CGSize(width: 1440, height: 900), to: dir, "break")

        s.stage(remaining: 33)
        save(HeadsUpCard(s: s, lead: 60, line: Scheduler.headsUpLines[0]).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background { wall },
             size: CGSize(width: 720, height: 240), to: dir, "headsup")
        s.stage(remaining: 5)
        save(FollowerPill(s: s).frame(maxWidth: .infinity, maxHeight: .infinity).background { wall }, size: CGSize(width: 360, height: 120), to: dir, "follower")

        s.stage(remaining: 1112)
        for (tab, name) in [(0, "panel-now"), (1, "panel-stats")] {
            save(PanelChrome(tab: tab, s: s).frame(maxWidth: .infinity, maxHeight: .infinity).background { wall }, size: CGSize(width: 400, height: tab == 0 ? 470 : 640), to: dir, name)
        }
        for pane in Pane.allCases {
            let slug = pane.rawValue.lowercased().replacingOccurrences(of: " / ", with: "-").replacingOccurrences(of: " ", with: "-")
            save(SettingsView(pane: pane), size: CGSize(width: 780, height: 600), to: dir, "settings-\(slug)")
        }
        let bar = Image(nsImage: MenuBarIcon.image(text: "20m")).foregroundStyle(.white).scaleEffect(3)
        save(ZStack { Color(white: 0.12); bar }, size: CGSize(width: 240, height: 90), to: dir, "menubar")
    }

    private struct PanelChrome: View {
        let tab: Int
        let s: Scheduler
        var body: some View {
            MenuPanel(s: s, updater: Updater.shared, tab: tab)
                .background(Color(red: 0.13, green: 0.12, blue: 0.16).opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
                .shadow(radius: 20)
        }
    }

    private static func save<V: View>(_ view: V, size: CGSize, to dir: URL, _ name: String) {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark).frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }
}
