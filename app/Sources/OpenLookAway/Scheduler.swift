import AppKit
import Observation

/// UserDefaults keys. Views bind with @AppStorage, the scheduler reads them live every tick.
enum Key {
    static let workMinutes = "workMinutes"
    static let breakSeconds = "breakSeconds"
    static let longBreakEvery = "longBreakEvery"
    static let longBreakMinutes = "longBreakMinutes"
    static let breakMode = "breakMode"            // 0 casual, 1 balanced, 2 hardcore
    static let snoozesPerDay = "snoozesPerDay"
    static let escAction = "escAction"            // 0 skip, 1 snooze 5 min
    static let lockOnBreak = "lockOnBreak"
    static let headsUpLead = "headsUpLead"        // seconds before a break, 0 = off
    static let headsUpVisible = "headsUpVisible"  // seconds the card stays up
    static let floatingCountdown = "floatingCountdown"
    static let alertPosition = "alertPosition"    // 0 left, 1 centre, 2 right
    static let idleResetMinutes = "idleResetMinutes"
    static let pauseForCalls = "pauseForCalls"
    static let pauseForVideo = "pauseForVideo"
    static let pauseForFullscreen = "pauseForFullscreen"
    static let blinkMinutes = "blinkMinutes"
    static let postureMinutes = "postureMinutes"
    static let soundStart = "soundStart"
    static let soundEnd = "soundEnd"
    static let soundName = "soundName"
    static let volume = "volume"
    static let background = "background"          // 0 blurred wallpaper, 1 gradient, 2 custom image
    static let customImage = "customImage"
    static let customMessages = "customMessages"
    static let showTimerInMenuBar = "showTimerInMenuBar"
    static let ignoredMicApps = "ignoredMicApps"     // bundle IDs, e.g. dictation apps that keep the mic open

    static let defaults: [String: Any] = [
        workMinutes: 20, breakSeconds: 20, longBreakEvery: 3, longBreakMinutes: 5,
        breakMode: 0, snoozesPerDay: 3, escAction: 0, lockOnBreak: false,
        headsUpLead: 60, headsUpVisible: 8, floatingCountdown: true, alertPosition: 1,
        idleResetMinutes: 5, pauseForCalls: true, pauseForVideo: false, pauseForFullscreen: false,
        blinkMinutes: 0, postureMinutes: 30,
        soundStart: false, soundEnd: true, soundName: "Glass", volume: 0.7,
        background: 0, customImage: "", customMessages: "", showTimerInMenuBar: true,
        // Dictation apps keep the mic warm; they aren't calls.
        ignoredMicApps: ["com.kitlangton.Hex", "com.superduper.superwhisper", "com.electron.wispr-flow",
                         "com.goodsnooze.MacWhisper", "com.prakashjoshipax.VoiceInk"],
    ]
}

private let d = UserDefaults.standard

/// Today's numbers, persisted as JSON and reset at midnight.
struct DayStats: Codable {
    var day = ""
    var taken = 0, takenSeconds = 0
    var natural = 0, naturalSeconds = 0
    var skipped = 0, snoozed = 0
    var screenSeconds = 0, longestStretch = 0

    /// 100 = perfect pacing. Skips, snoozes and very long stretches cost points.
    var score: Int {
        let overtime = max(0, longestStretch - 2 * d.integer(forKey: Key.workMinutes) * 60) / 60
        return max(0, min(100, 100 - skipped * 12 - snoozed * 5 - min(overtime, 30)))
    }
}

@MainActor @Observable
final class Scheduler {
    static let shared = Scheduler()

    enum Phase { case working, onBreak }

    private(set) var phase = Phase.working
    /// Seconds until the next break while working, seconds left while on a break.
    private(set) var remaining: Int
    private(set) var breakLength = 0
    private(set) var isLongBreak = false
    private(set) var title = ""
    private(set) var message = ""
    /// Manual pause. `.distantFuture` means "until I resume".
    private(set) var pausedUntil: Date?
    /// Why the timer is currently frozen on its own ("In a call", "Away"...).
    private(set) var autoPauseReason: String?
    private(set) var stats = DayStats()
    /// The app whose microphone use is pausing breaks, so the panel can offer to ignore it.
    private(set) var micApp: NSRunningApplication?
    /// "Resume anyway": ignore the current auto-pause until its cause goes away.
    private var overridingAutoPause = false

    private var breaksSinceLong = 0
    private var warned = false
    private var away: Date?
    private var stretch = 0
    private var nextBlink = Date.distantFuture
    private var nextPosture = Date.distantFuture
    private var previousApp: NSRunningApplication?

    var workSeconds: Int { d.integer(forKey: Key.workMinutes) * 60 }
    var snoozesLeft: Int { max(0, d.integer(forKey: Key.snoozesPerDay) - stats.snoozed) }
    var isPaused: Bool { pausedUntil != nil }
    var breakElapsed: Int { breakLength - remaining }

    private init() {
        d.register(defaults: Key.defaults)
        remaining = d.integer(forKey: Key.workMinutes) * 60
        if let data = d.data(forKey: "stats"), let s = try? JSONDecoder().decode(DayStats.self, from: data), s.day == Self.today {
            stats = s
        }
        stats.day = Self.today
        resetReminders()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { Scheduler.shared.tick() }
        }
        // Sleeping the Mac counts as a break.
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Scheduler.shared.restart() }
            }
        }
    }

    var status: String {
        if phase == .onBreak { return "On a break" }
        if let until = pausedUntil {
            return until == .distantFuture ? "Paused" : "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if let reason = autoPauseReason { return "Paused · \(reason)" }
        return "Next break in \(clock(remaining))"
    }

    // MARK: - Loop

    private func tick() {
        if stats.day != Self.today { stats = DayStats(day: Self.today); save() }
        if phase == .onBreak {
            remaining -= 1
            if remaining <= 0 { endBreak(completed: true) }
            return
        }
        if let until = pausedUntil {
            if until > .now { return }
            pausedUntil = nil
            restart()
        }

        let idle = System.idleSeconds()
        if idle >= Double(d.integer(forKey: Key.idleResetMinutes) * 60) {
            // They walked away: that was the break. Start fresh when they're back.
            if away == nil {
                away = Date(timeIntervalSinceNow: -idle)
                stats.natural += 1
                save()
            }
            autoPauseReason = "Away"
            restart()
            return
        }
        if let since = away {
            stats.naturalSeconds += Int(Date.now.timeIntervalSince(since))
            away = nil
            save()
        }
        let reason = autoPause()
        if reason == nil { overridingAutoPause = false }
        if let reason, !overridingAutoPause {
            autoPauseReason = reason
            HUD.hideAlerts()
            return
        }
        autoPauseReason = nil
        remaining -= 1

        if idle < 60 {
            stats.screenSeconds += 1
            stretch += 1
            stats.longestStretch = max(stats.longestStretch, stretch)
            if stats.screenSeconds % 30 == 0 { save() }
        }

        if Date.now >= nextBlink {
            HUD.nudge(.blink)
            nextBlink = next(Key.blinkMinutes)
        } else if Date.now >= nextPosture {
            HUD.nudge(.posture)
            nextPosture = next(Key.postureMinutes)
        }

        let lead = d.integer(forKey: Key.headsUpLead)
        if lead > 0, !warned, remaining <= lead, remaining > 5 {
            warned = true
            HUD.headsUp(self)
        }
        if d.bool(forKey: Key.floatingCountdown), remaining <= 5, remaining > 0 {
            HUD.floatingCountdown(self)
        }
        if remaining <= 0 { startBreak() }
    }

    private func autoPause() -> String? {
        micApp = nil
        if d.bool(forKey: Key.pauseForCalls) {
            if let apps = System.appsUsingMic() {
                let ignored = Set(d.stringArray(forKey: Key.ignoredMicApps) ?? [])
                if let app = apps.first(where: { !ignored.contains($0.bundleIdentifier ?? "") }) {
                    micApp = app
                    return "\(app.localizedName ?? "An app") is using the mic"
                }
            } else if System.micInUse() {
                return "In a call"
            }
        }
        if d.bool(forKey: Key.pauseForVideo) && System.videoPlaying() { return "Watching a video" }
        if d.bool(forKey: Key.pauseForFullscreen) && System.frontAppIsFullscreen() { return "Fullscreen app" }
        return nil
    }

    // MARK: - Actions

    func startBreak() {
        let every = d.integer(forKey: Key.longBreakEvery)
        isLongBreak = every > 0 && breaksSinceLong + 1 >= every
        breakLength = isLongBreak ? d.integer(forKey: Key.longBreakMinutes) * 60 : d.integer(forKey: Key.breakSeconds)
        remaining = breakLength
        (title, message) = pickCopy()
        phase = .onBreak
        pausedUntil = nil
        HUD.hideAlerts()
        previousApp = NSWorkspace.shared.frontmostApplication
        Overlay.show(self)
        if d.bool(forKey: Key.soundStart) { playSound() }
        if d.bool(forKey: Key.lockOnBreak) { System.lockScreen() }
    }

    func endBreak(completed: Bool) {
        if completed {
            stats.taken += 1
            stats.takenSeconds += breakLength
            breaksSinceLong = isLongBreak ? 0 : breaksSinceLong + 1
            if d.bool(forKey: Key.soundEnd) { playSound() }
        } else {
            stats.skipped += 1
        }
        save()
        phase = .working
        Overlay.hide()
        restart()
        previousApp?.activate()
    }

    /// Push the upcoming (or current) break back. Uses one of today's snoozes.
    func snooze(minutes: Int) {
        guard snoozesLeft > 0 else { return }
        stats.snoozed += 1
        save()
        if phase == .onBreak {
            phase = .working
            Overlay.hide()
            previousApp?.activate()
        }
        HUD.hideAlerts()
        remaining = minutes * 60
        warned = false
    }

    func skipNext() {
        HUD.hideAlerts()
        if phase == .onBreak { return endBreak(completed: false) }
        stats.skipped += 1
        save()
        restart()
    }

    func pause(minutes: Int?) {
        if phase == .onBreak { endBreak(completed: false) }
        HUD.hideAlerts()
        pausedUntil = minutes.map { .now.addingTimeInterval(Double($0) * 60) } ?? .distantFuture
    }

    /// Keep counting even though a smart-pause condition is active.
    func resumeAnyway() {
        overridingAutoPause = true
        autoPauseReason = nil
    }

    /// Never pause for this app's microphone use again (dictation tools keep the mic open).
    func ignoreMicApp() {
        guard let id = micApp?.bundleIdentifier else { return }
        d.set((d.stringArray(forKey: Key.ignoredMicApps) ?? []) + [id], forKey: Key.ignoredMicApps)
        micApp = nil
        autoPauseReason = nil
    }

    func resume() {
        pausedUntil = nil
        restart()
    }

    func restart() {
        guard phase == .working else { return }
        remaining = workSeconds
        warned = false
        stretch = 0
        HUD.hideAlerts()
        resetReminders()
    }

    func playSound() {
        guard let s = NSSound(named: d.string(forKey: Key.soundName) ?? "Glass") else { return }
        s.volume = d.float(forKey: Key.volume)
        s.play()
    }

    /// Puts the scheduler in a given state for `--snapshots`.
    func stage(remaining: Int, onBreak: Bool = false) {
        phase = onBreak ? .onBreak : .working
        breakLength = 20
        self.remaining = remaining
        (title, message) = Self.copy[0]
        stats = DayStats(day: Self.today, taken: 9, takenSeconds: 180, natural: 3, naturalSeconds: 2460,
                         skipped: 1, snoozed: 1, screenSeconds: 18900, longestStretch: 1920)
    }

    // MARK: - Helpers

    private func save() {
        d.set(try? JSONEncoder().encode(stats), forKey: "stats")
    }

    private func next(_ key: String) -> Date {
        let m = d.integer(forKey: key)
        return m > 0 ? .now.addingTimeInterval(Double(m) * 60) : .distantFuture
    }

    private func resetReminders() {
        nextBlink = next(Key.blinkMinutes)
        nextPosture = next(Key.postureMinutes)
    }

    private func pickCopy() -> (String, String) {
        if isLongBreak { return ("Time for a longer break", "Stand up, stretch, and walk around for a few minutes.") }
        let (t, m) = Self.copy.randomElement()!
        let custom = (d.string(forKey: Key.customMessages) ?? "")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (t, custom.randomElement() ?? m)
    }

    static let copy = [
        ("Rest your eyes", "Pick something far away and let your focus soften until the timer ends."),
        ("Find the horizon", "Look out of a window or across the room. Let your eyes wander."),
        ("Look far away", "Twenty feet or more. Your eye muscles relax when they focus far."),
        ("Blink and breathe", "Slow blinks, slow breaths. The screen will still be here."),
        ("Soften your gaze", "Unclench your jaw, drop your shoulders, look into the distance."),
    ]

    static let headsUpLines = [
        "Nearly there. Finish your thought.",
        "A short break is coming up.",
        "Your eyes will thank you in a moment.",
        "Wrap up that sentence. Break soon.",
    ]

    private static var today: String { Date.now.formatted(.iso8601.year().month().day()) }
}

func clock(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
}

/// "1h 12m", "45m", "30s".
func duration(_ seconds: Int) -> String {
    if seconds >= 3600 { return "\(seconds / 3600)h \(seconds / 60 % 60)m" }
    return seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
}
