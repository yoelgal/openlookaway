import ServiceManagement
import SwiftUI

@main
struct OpenLookAwayApp: App {
    @State private var s = Scheduler.shared
    @State private var updater = Updater.shared
    @AppStorage(Key.showTimerInMenuBar) private var showTimer = true

    init() {
        Snapshots.runIfRequested()
        // First launch: start at login and say hello, since menu bar apps are otherwise invisible.
        if !UserDefaults.standard.bool(forKey: "launched") {
            UserDefaults.standard.set(true, forKey: "launched")
            try? SMAppService.mainApp.register()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                HUD.toast("OpenLookAway is running in your menu bar")
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(s: s, updater: updater)
        } label: {
            Image(nsImage: MenuBarIcon.image(text: label))
        }
        .menuBarExtraStyle(.window)

        Window("OpenLookAway Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }

    /// "20m" normally, "0:45" in the last minute, nil when hidden.
    private var label: String? {
        if s.isPaused || s.autoPauseReason != nil { return showTimer ? "Paused" : nil }
        guard showTimer, s.phase == .working else { return nil }
        return s.remaining >= 60 ? "\(Int((Double(s.remaining) / 60).rounded(.up)))m" : "0:\(String(format: "%02d", max(s.remaining, 0)))"
    }
}
