import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case general = "General"
    case breaks = "Screen Breaks", smartPause = "Smart Pause", wellness = "Wellness Reminders"
    case alerts = "Alerts / Nudges", sounds = "Sounds", breakScreen = "Break Screen"
    case about = "About"

    var id: Self { self }

    var tile: Tile {
        switch self {
        case .general: Tile(symbol: "gearshape.fill", colors: [Color(red: 0.55, green: 0.36, blue: 0.96), .brandPink])
        case .breaks: Tile(symbol: "eye.fill")
        case .smartPause: Tile(symbol: "pause.fill")
        case .wellness: Tile(symbol: "heart.fill")
        case .alerts: Tile(symbol: "bell.fill", colors: [Color(red: 0.95, green: 0.33, blue: 0.55), Color(red: 0.98, green: 0.45, blue: 0.45)])
        case .sounds: Tile(symbol: "speaker.wave.2.fill", colors: [Color(red: 0.96, green: 0.30, blue: 0.35), .brandOrange])
        case .breakScreen: Tile(symbol: "paintbrush.pointed.fill", colors: [.brandOrange, Color(red: 0.96, green: 0.45, blue: 0.25)])
        case .about: Tile(symbol: "info", colors: [Color(red: 0.98, green: 0.78, blue: 0.25), Color(red: 0.95, green: 0.60, blue: 0.15)])
        }
    }

    var tileLarge: Tile {
        var t = tile
        t.size = 28
        return t
    }

    static let groups: [(String?, [Pane])] = [
        (nil, [.general]),
        ("Focus & Wellbeing", [.breaks, .smartPause, .wellness]),
        ("Behavior & Feedback", [.alerts, .sounds, .breakScreen]),
        ("OpenLookAway", [.about]),
    ]
}

struct SettingsView: View {
    @State var pane: Pane = .breaks

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    pane.tileLarge
                    Text(pane.rawValue).font(.system(size: 17, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 22)
                .frame(height: 58)
                Divider()
                Form { content(pane) }.formStyle(.grouped)
            }
        }
        .background(Color(red: 0.15, green: 0.15, blue: 0.18))
        .frame(width: 780, height: 600)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.groups, id: \.1.first!.id) { title, panes in
                if let title {
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4)
                }
                ForEach(panes) { p in
                    Button { pane = p } label: {
                        HStack(spacing: 9) {
                            p.tile
                            Text(p.rawValue).font(.system(size: 13))
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(pane == p ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 40)
        .frame(width: 220)
        .background(Color(red: 0.10, green: 0.10, blue: 0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.06)))
        .padding(8)
    }

    @ViewBuilder private func content(_ p: Pane) -> some View {
        switch p {
        case .general: GeneralPane()
        case .breaks: BreaksPane()
        case .smartPause: SmartPausePane()
        case .wellness: WellnessPane()
        case .alerts: AlertsPane()
        case .sounds: SoundsPane()
        case .breakScreen: BreakScreenPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @AppStorage(Key.showTimerInMenuBar) private var showTimer = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Section {
            Toggle("Open OpenLookAway at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            Toggle("Show countdown in the menu bar", isOn: $showTimer)
        }
        Section {
            LabeledContent("Updates") {
                Button("Check for Updates…") { Updater.shared.checkInteractively() }
            }
        }
    }
}

private struct BreaksPane: View {
    @AppStorage(Key.workMinutes) private var workMinutes = 20
    @AppStorage(Key.breakSeconds) private var breakSeconds = 20
    @AppStorage(Key.longBreakEvery) private var longBreakEvery = 3
    @AppStorage(Key.longBreakMinutes) private var longBreakMinutes = 5
    @AppStorage(Key.breakMode) private var mode = 0
    @AppStorage(Key.snoozesPerDay) private var snoozes = 3
    @AppStorage(Key.escAction) private var escAction = 0
    @AppStorage(Key.lockOnBreak) private var lockOnBreak = false

    var body: some View {
        Section("General") {
            Picker("Show breaks every", selection: $workMinutes) {
                ForEach([10, 15, 20, 25, 30, 40, 45, 50, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
            }
            .onChange(of: workMinutes) { Scheduler.shared.restart() }
            Picker("Break duration", selection: $breakSeconds) {
                ForEach([10, 20, 30, 45, 60, 90, 120, 180, 300], id: \.self) { Text($0 < 60 ? "\($0) seconds" : "\($0 / 60) min\($0 % 60 > 0 ? " \($0 % 60) sec" : "")").tag($0) }
            }
            Picker("Long breaks", selection: $longBreakEvery) {
                Text("Off").tag(0)
                ForEach(2...6, id: \.self) { Text("Every \($0)\(["", "", "nd", "rd", "th", "th", "th"][$0]) break").tag($0) }
            }
            if longBreakEvery > 0 {
                Picker("Long break duration", selection: $longBreakMinutes) {
                    ForEach([2, 3, 5, 10, 15], id: \.self) { Text("\($0) minutes").tag($0) }
                }
            }
        }
        Section("Break enforcement") {
            ChoiceCards(selection: $mode, options: [
                .init(tag: 0, title: "Casual", subtitle: "Skip anytime", preview: AnyView(SkipPreview(symbol: "chevron.forward.2"))),
                .init(tag: 1, title: "Balanced", subtitle: "Skip after a pause", preview: AnyView(SkipPreview(symbol: "circle.dotted"))),
                .init(tag: 2, title: "Hardcore", subtitle: "No skips allowed", preview: AnyView(SkipPreview(symbol: "nosign", dimmed: true))),
            ])
            Stepper("Snoozes allowed per day: \(snoozes)", value: $snoozes, in: 0...20)
        }
        Section("More") {
            Picker("Double Esc on the break screen", selection: $escAction) {
                Text("Skips the break").tag(0)
                Text("Snoozes for 5 minutes").tag(1)
            }
            Toggle("Lock my Mac when a break starts", isOn: $lockOnBreak)
        }
    }
}

private struct SkipPreview: View {
    let symbol: String
    var dimmed = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.55), Color(red: 0.85, green: 0.30, blue: 0.35), Color(red: 0.95, green: 0.60, blue: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Label("Skip Break", systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.22), in: Capsule())
                .foregroundStyle(.white.opacity(dimmed ? 0.45 : 1))
        }
    }
}

private struct SmartPausePane: View {
    @AppStorage(Key.pauseForCalls) private var calls = true
    @AppStorage(Key.pauseForVideo) private var video = false
    @AppStorage(Key.pauseForFullscreen) private var fullscreen = false
    @AppStorage(Key.idleResetMinutes) private var idleReset = 5
    @State private var ignored = UserDefaults.standard.stringArray(forKey: Key.ignoredMicApps) ?? []

    var body: some View {
        Section {
            Toggle("Meetings and calls", isOn: $calls)
            Toggle("Video playback", isOn: $video)
            Toggle("Fullscreen apps and games", isOn: $fullscreen)
        } header: {
            Text("Pause breaks during")
        } footer: {
            Text("Calls are detected when any app is using your microphone. Video playback is detected when an app keeps your display awake.")
                .foregroundStyle(.secondary)
        }
        if !ignored.isEmpty {
            Section {
                ForEach(ignored, id: \.self) { id in
                    HStack {
                        Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id)
                        Spacer()
                        Button("Remove") {
                            ignored.removeAll { $0 == id }
                            UserDefaults.standard.set(ignored, forKey: Key.ignoredMicApps)
                        }
                    }
                }
            } header: {
                Text("Apps that never pause breaks")
            } footer: {
                Text("Dictation apps keep the microphone open all the time. Use \"Ignore\" in the menu bar panel to add one here.")
                    .foregroundStyle(.secondary)
            }
        }
        Section {
            Picker("Count it as a break after", selection: $idleReset) {
                ForEach([2, 3, 5, 10, 15], id: \.self) { Text("\($0) minutes away").tag($0) }
            }
        } header: {
            Text("Natural breaks")
        } footer: {
            Text("Step away from your Mac or put it to sleep and the timer starts fresh when you're back.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct WellnessPane: View {
    @AppStorage(Key.blinkMinutes) private var blink = 0
    @AppStorage(Key.postureMinutes) private var posture = 30

    var body: some View {
        Section {
            Picker(selection: $posture) {
                Text("Off").tag(0)
                ForEach([15, 20, 30, 45, 60], id: \.self) { Text("Every \($0) minutes").tag($0) }
            } label: {
                Label { Text("Posture reminder") } icon: { Tile(symbol: "figure.stand") }
            }
            Picker(selection: $blink) {
                Text("Off").tag(0)
                ForEach([10, 15, 20, 30], id: \.self) { Text("Every \($0) minutes").tag($0) }
            } label: {
                Label { Text("Blink reminder") } icon: { Tile(symbol: "eye") }
            }
        } footer: {
            Text("A small animated nudge appears for a few seconds, then gets out of your way.").foregroundStyle(.secondary)
        }
        Section {
            HStack {
                Button("Preview posture") { HUD.nudge(.posture) }
                Button("Preview blink") { HUD.nudge(.blink) }
            }
        }
    }
}

private struct AlertsPane: View {
    @AppStorage(Key.alertPosition) private var position = 1
    @AppStorage(Key.headsUpLead) private var lead = 60
    @AppStorage(Key.headsUpVisible) private var visible = 8
    @AppStorage(Key.floatingCountdown) private var floating = true

    var body: some View {
        Section("Positioning") {
            ChoiceCards(selection: $position, options: [0, 1, 2].map { i in
                .init(tag: i, title: ["Top left", "Top center", "Top right"][i], subtitle: nil, preview: AnyView(PositionPreview(index: i)))
            })
        }
        Section("Break reminder") {
            Picker("Show a heads-up", selection: $lead) {
                Text("Never").tag(0)
                Text("30 seconds before").tag(30)
                Text("1 minute before").tag(60)
                Text("2 minutes before").tag(120)
            }
            if lead > 0 {
                Picker("Keep it visible for", selection: $visible) {
                    ForEach([5, 8, 15, 30], id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }
            Toggle("Show a countdown next to the cursor for the last 5 seconds", isOn: $floating)
        }
        Section {
            Button("Preview heads-up") { HUD.headsUp(Scheduler.shared) }
        }
    }
}

private struct PositionPreview: View {
    let index: Int
    var body: some View {
        ZStack(alignment: [.topLeading, .top, .topTrailing][index]) {
            if let url = Bundle.main.url(forResource: "wall-blue", withExtension: "jpg"), let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
            }
            RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.7)).frame(width: 46, height: 18).padding(6)
        }
        .clipped()
    }
}

private struct SoundsPane: View {
    @AppStorage(Key.soundStart) private var start = false
    @AppStorage(Key.soundEnd) private var end = true
    @AppStorage(Key.soundName) private var name = "Glass"
    @AppStorage(Key.volume) private var volume = 0.7

    static let sounds = ["Glass", "Tink", "Purr", "Hero", "Ping", "Pop", "Submarine", "Blow", "Bottle", "Frog", "Funk", "Morse", "Sosumi"]

    var body: some View {
        Section {
            Toggle("Play a sound when the break begins", isOn: $start)
            Toggle("Play a sound when the break ends", isOn: $end)
            Picker("Sound", selection: $name) {
                ForEach(Self.sounds, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: name) { Scheduler.shared.playSound() }
            LabeledContent("Volume") {
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1) { editing in if !editing { Scheduler.shared.playSound() } }
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .frame(width: 220)
            }
        }
    }
}

private struct BreakScreenPane: View {
    @AppStorage(Key.background) private var background = 0
    @AppStorage(Key.customImage) private var customImage = ""
    @AppStorage(Key.customMessages) private var stored = ""
    @State private var messages: [String] = []
    @State private var selected: Int?

    var body: some View {
        Section("Background") {
            ChoiceCards(selection: $background, options: [
                .init(tag: 0, title: "Blurred wallpaper", subtitle: nil, preview: AnyView(WallpaperPreview())),
                .init(tag: 1, title: "Gradient", subtitle: nil, preview: AnyView(
                    LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.45), Color(red: 0.55, green: 0.18, blue: 0.55), Color(red: 0.95, green: 0.55, blue: 0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))),
                .init(tag: 2, title: "Custom image", subtitle: nil, preview: AnyView(CustomImagePreview(path: customImage))),
            ])
            .onChange(of: background) { _, new in if new == 2 && customImage.isEmpty { pickImage() } }
            if background == 2 {
                LabeledContent("Image") {
                    Button(customImage.isEmpty ? "Choose…" : URL(fileURLWithPath: customImage).lastPathComponent) { pickImage() }
                }
            }
        }
        Section {
            List(selection: $selected) {
                ForEach(messages.indices, id: \.self) { i in
                    TextField("Message", text: Binding(get: { messages[i] }, set: { messages[i] = $0; save() }))
                        .textFieldStyle(.plain)
                        .tag(i)
                }
            }
            .frame(minHeight: 110)
            HStack(spacing: 4) {
                Button { messages.append("Look out of the window for a moment"); save() } label: { Image(systemName: "plus") }
                Button {
                    if let i = selected, messages.indices.contains(i) { messages.remove(at: i); selected = nil; save() }
                } label: { Image(systemName: "minus") }
                .disabled(selected == nil)
                Spacer()
                Text("A random message is shown on each break").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Custom messages")
        }
        .onAppear { messages = stored.split(separator: "\n").map(String.init) }
        Section {
            Button("Preview break screen") { Scheduler.shared.startBreak() }
        }
    }

    private func save() {
        stored = messages.joined(separator: "\n")
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { customImage = url.path } else if customImage.isEmpty { background = 0 }
    }
}

private struct WallpaperPreview: View {
    var body: some View {
        if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen), let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).blur(radius: 6)
        } else {
            LinearGradient(colors: [.indigo, .cyan], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct CustomImagePreview: View {
    let path: String
    var body: some View {
        if !path.isEmpty, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary)
                Image(systemName: "photo.badge.plus").font(.title3).foregroundStyle(.secondary)
            }
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        Section {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text("OpenLookAway").font(.title2.weight(.semibold))
                Text("Version \(Updater.shared.current)").foregroundStyle(.secondary)
                Text("A free, open-source break reminder for your Mac. MIT licensed.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button("Check for Updates…") { Updater.shared.checkInteractively() }
                    Link("GitHub", destination: URL(string: "https://github.com/\(Updater.repo)")!)
                    Link("Website", destination: URL(string: "https://lookaway.yoelgal.com")!)
                }
                .padding(.top, 6)
                Text("Inspired by LookAway (lookaway.com). Not affiliated.").font(.caption).foregroundStyle(.tertiary).padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Picture choice cards

private struct ChoiceCards: View {
    struct Option {
        let tag: Int
        let title: String
        let subtitle: String?
        let preview: AnyView
    }

    @Binding var selection: Int
    let options: [Option]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(options, id: \.tag) { o in
                Button { selection = o.tag } label: {
                    VStack(spacing: 6) {
                        o.preview
                            .frame(height: 70)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection == o.tag ? Color.accentColor : .clear, lineWidth: 3))
                        Text(o.title).font(.system(size: 12, weight: selection == o.tag ? .semibold : .regular))
                        if let s = o.subtitle { Text(s).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
