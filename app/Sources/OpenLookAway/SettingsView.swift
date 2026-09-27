import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Key.workMinutes) private var workMinutes = 20
    @AppStorage(Key.breakSeconds) private var breakSeconds = 20
    @AppStorage(Key.longBreakEvery) private var longBreakEvery = 3
    @AppStorage(Key.longBreakMinutes) private var longBreakMinutes = 5
    @AppStorage(Key.warnSeconds) private var warnSeconds = 10
    @AppStorage(Key.idleResetMinutes) private var idleResetMinutes = 5
    @AppStorage(Key.pauseForCalls) private var pauseForCalls = true
    @AppStorage(Key.pauseForFullscreen) private var pauseForFullscreen = false
    @AppStorage(Key.blinkMinutes) private var blinkMinutes = 0
    @AppStorage(Key.postureMinutes) private var postureMinutes = 30
    @AppStorage(Key.allowSkip) private var allowSkip = true
    @AppStorage(Key.playSound) private var playSound = true
    @AppStorage(Key.showTimerInMenuBar) private var showTimer = true
    @AppStorage(Key.customMessages) private var customMessages = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Breaks") {
                Stepper("Break every **\(workMinutes) min**", value: $workMinutes, in: 1...120, step: workMinutes < 5 ? 1 : 5)
                Stepper("Break lasts **\(breakSeconds) sec**", value: $breakSeconds, in: 5...300, step: 5)
                Picker("Longer break", selection: $longBreakEvery) {
                    Text("Never").tag(0)
                    ForEach(2...6, id: \.self) { Text("Every \($0) breaks").tag($0) }
                }
                if longBreakEvery > 0 {
                    Stepper("Longer break lasts **\(longBreakMinutes) min**", value: $longBreakMinutes, in: 1...30)
                }
                Picker("Heads-up before a break", selection: $warnSeconds) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 30, 60], id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Toggle("Allow skipping breaks", isOn: $allowSkip)
                Toggle("Play a sound when a break ends", isOn: $playSound)
            }

            Section {
                Toggle("Pause during calls and meetings", isOn: $pauseForCalls)
                Toggle("Pause while an app is fullscreen", isOn: $pauseForFullscreen)
                Stepper("Reset after **\(idleResetMinutes) min** away", value: $idleResetMinutes, in: 1...30)
            } header: {
                Text("Smart pause")
            } footer: {
                Text("Calls are detected when your microphone is in use. Stepping away from your Mac counts as a break.")
                    .foregroundStyle(.secondary)
            }

            Section("Wellness nudges") {
                Picker("Blink reminder", selection: $blinkMinutes) {
                    Text("Off").tag(0)
                    ForEach([10, 15, 20, 30], id: \.self) { Text("Every \($0) min").tag($0) }
                }
                Picker("Posture reminder", selection: $postureMinutes) {
                    Text("Off").tag(0)
                    ForEach([15, 30, 45, 60], id: \.self) { Text("Every \($0) min").tag($0) }
                }
            }

            Section {
                TextEditor(text: $customMessages)
                    .font(.body)
                    .frame(height: 70)
            } header: {
                Text("Break messages")
            } footer: {
                Text("One per line. Leave empty to use the built-in messages.").foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Toggle("Show countdown in menu bar", isOn: $showTimer)
                LabeledContent("Version", value: Updater.shared.current)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/\(Updater.repo)")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: workMinutes) { Scheduler.shared.restart() }
    }
}
