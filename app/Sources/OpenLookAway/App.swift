import ServiceManagement
import SwiftUI

@main
struct OpenLookAwayApp: App {
    @State private var s = Scheduler.shared
    @State private var updater = Updater.shared
    @AppStorage(Key.showTimerInMenuBar) private var showTimer = true

    init() {
        // First launch: start at login and say hello, since menu bar apps are otherwise invisible.
        if !UserDefaults.standard.bool(forKey: "launched") {
            UserDefaults.standard.set(true, forKey: "launched")
            try? SMAppService.mainApp.register()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                HUD.remind("OpenLookAway is running in your menu bar", symbol: "eye")
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(s: s, updater: updater)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: s.isPaused || s.autoPauseReason != nil ? "eye.slash" : "eye")
                if showTimer && s.phase == .working && !s.isPaused && s.autoPauseReason == nil {
                    Text(s.remaining >= 60 ? "\(s.remaining / 60)m" : clock(s.remaining)).monospacedDigit()
                }
            }
        }

        Window("OpenLookAway Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

struct MenuContent: View {
    let s: Scheduler
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(s.status)
        Divider()
        Button("Take a Break Now") { s.startBreak() }.keyboardShortcut("b")
        Button("Skip Next Break") { s.skipNext() }
        if s.isPaused {
            Button("Resume") { s.resume() }.keyboardShortcut("p")
        } else {
            Menu("Pause") {
                Button("For 30 Minutes") { s.pause(minutes: 30) }
                Button("For 1 Hour") { s.pause(minutes: 60) }
                Button("For 2 Hours") { s.pause(minutes: 120) }
                Button("Until I Resume") { s.pause(minutes: nil) }
            }
        }
        Button("Restart Timer") { s.restart() }
        Divider()
        Text("Today: \(s.takenToday) taken · \(s.skippedToday) skipped")
        Divider()
        if let v = updater.available {
            Button(updater.installing ? "Installing \(v)…" : "Update to \(v)") { updater.install() }
                .disabled(updater.installing)
        }
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") { updater.checkInteractively() }
        Divider()
        Button("Quit OpenLookAway") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
