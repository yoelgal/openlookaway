import AppKit
import Observation

/// UserDefaults keys. Views bind with @AppStorage, the scheduler reads them live every tick.
enum Key {
    static let workMinutes = "workMinutes"
    static let breakSeconds = "breakSeconds"
    static let longBreakEvery = "longBreakEvery"
    static let longBreakMinutes = "longBreakMinutes"
    static let warnSeconds = "warnSeconds"
    static let idleResetMinutes = "idleResetMinutes"
    static let pauseForCalls = "pauseForCalls"
    static let pauseForFullscreen = "pauseForFullscreen"
    static let blinkMinutes = "blinkMinutes"
    static let postureMinutes = "postureMinutes"
    static let allowSkip = "allowSkip"
    static let playSound = "playSound"
    static let showTimerInMenuBar = "showTimerInMenuBar"
    static let customMessages = "customMessages"

    static let defaults: [String: Any] = [
        workMinutes: 20, breakSeconds: 20, longBreakEvery: 3, longBreakMinutes: 5,
        warnSeconds: 10, idleResetMinutes: 5, pauseForCalls: true, pauseForFullscreen: false,
        blinkMinutes: 0, postureMinutes: 30, allowSkip: true, playSound: true,
        showTimerInMenuBar: true, customMessages: "",
    ]
}

private let d = UserDefaults.standard

@MainActor @Observable
final class Scheduler {
    static let shared = Scheduler()

    enum Phase { case working, onBreak }

    private(set) var phase = Phase.working
    /// Seconds until the next break while working, seconds left while on a break.
    private(set) var remaining: Int
    private(set) var isLongBreak = false
    private(set) var message = ""
    /// Manual pause. `.distantFuture` means "until I resume".
    private(set) var pausedUntil: Date?
    /// Why the timer is currently frozen on its own ("In a call", "Away"...).
    private(set) var autoPauseReason: String?
    private(set) var takenToday = 0
    private(set) var skippedToday = 0

    private var breaksSinceLong = 0
    private var warned = false
    private var nextBlink = Date.distantFuture
    private var nextPosture = Date.distantFuture
    private var previousApp: NSRunningApplication?

    private var workSeconds: Int { d.integer(forKey: Key.workMinutes) * 60 }

    private init() {
        d.register(defaults: Key.defaults)
        remaining = d.integer(forKey: Key.workMinutes) * 60
        loadStats()
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

    var isPaused: Bool { pausedUntil != nil }

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
        rollStatsDay()
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

        if System.idleSeconds() >= Double(d.integer(forKey: Key.idleResetMinutes) * 60) {
            // They walked away: that was the break. Start fresh when they're back.
            autoPauseReason = "Away"
            restart()
            return
        }
        if d.bool(forKey: Key.pauseForCalls) && System.micInUse() {
            autoPauseReason = "In a call"
            HUD.hide()
            return
        }
        if d.bool(forKey: Key.pauseForFullscreen) && System.frontAppIsFullscreen() {
            autoPauseReason = "Fullscreen app"
            HUD.hide()
            return
        }
        autoPauseReason = nil
        remaining -= 1

        if Date.now >= nextBlink {
            HUD.remind("Blink slowly a few times", symbol: "eye")
            nextBlink = next(Key.blinkMinutes)
        } else if Date.now >= nextPosture {
            HUD.remind("Sit up tall, shoulders down", symbol: "figure.stand")
            nextPosture = next(Key.postureMinutes)
        }

        let warn = d.integer(forKey: Key.warnSeconds)
        if warn > 0, !warned, remaining <= warn, remaining > 0 {
            warned = true
            HUD.headsUp(self)
        }
        if remaining <= 0 { startBreak() }
    }

    // MARK: - Actions

    func startBreak() {
        let every = d.integer(forKey: Key.longBreakEvery)
        isLongBreak = every > 0 && breaksSinceLong + 1 >= every
        remaining = isLongBreak ? d.integer(forKey: Key.longBreakMinutes) * 60 : d.integer(forKey: Key.breakSeconds)
        message = pickMessage()
        phase = .onBreak
        pausedUntil = nil
        HUD.hide()
        previousApp = NSWorkspace.shared.frontmostApplication
        Overlay.show(self)
    }

    func endBreak(completed: Bool) {
        if completed {
            takenToday += 1
            breaksSinceLong = isLongBreak ? 0 : breaksSinceLong + 1
            if d.bool(forKey: Key.playSound) { NSSound(named: "Glass")?.play() }
        } else {
            skippedToday += 1
        }
        saveStats()
        phase = .working
        Overlay.hide()
        restart()
        previousApp?.activate()
    }

    /// Push the upcoming (or current) break back by some minutes.
    func snooze(minutes: Int) {
        if phase == .onBreak {
            phase = .working
            Overlay.hide()
            previousApp?.activate()
        }
        HUD.hide()
        remaining = minutes * 60
        warned = false
    }

    func skipNext() {
        HUD.hide()
        if phase == .onBreak { endBreak(completed: false) } else { skippedToday += 1; saveStats(); restart() }
    }

    func pause(minutes: Int?) {
        if phase == .onBreak { endBreak(completed: false) }
        HUD.hide()
        pausedUntil = minutes.map { .now.addingTimeInterval(Double($0) * 60) } ?? .distantFuture
    }

    func resume() {
        pausedUntil = nil
        restart()
    }

    func restart() {
        guard phase == .working else { return }
        remaining = workSeconds
        warned = false
        HUD.hideHeadsUp()
        resetReminders()
    }

    // MARK: - Helpers

    private func next(_ key: String) -> Date {
        let m = d.integer(forKey: key)
        return m > 0 ? .now.addingTimeInterval(Double(m) * 60) : .distantFuture
    }

    private func resetReminders() {
        nextBlink = next(Key.blinkMinutes)
        nextPosture = next(Key.postureMinutes)
    }

    private func pickMessage() -> String {
        if isLongBreak { return "Stand up, stretch, and move around for a few minutes." }
        let custom = (d.string(forKey: Key.customMessages) ?? "")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (custom.isEmpty ? Self.messages : custom).randomElement()!
    }

    static let messages = [
        "Look at something at least 20 feet away.",
        "Let your eyes rest on the horizon.",
        "Blink slowly. Unclench your jaw.",
        "Roll your shoulders back and breathe out.",
        "Look out a window for a moment.",
        "Relax your face and soften your gaze.",
    ]

    // Stats reset at midnight.
    private var today: String { Date.now.formatted(.iso8601.year().month().day()) }

    private func loadStats() {
        guard d.string(forKey: "statsDay") == today else { return }
        takenToday = d.integer(forKey: "takenToday")
        skippedToday = d.integer(forKey: "skippedToday")
    }

    private func saveStats() {
        d.set(today, forKey: "statsDay")
        d.set(takenToday, forKey: "takenToday")
        d.set(skippedToday, forKey: "skippedToday")
    }

    private func rollStatsDay() {
        if d.string(forKey: "statsDay") != today, takenToday + skippedToday > 0 {
            takenToday = 0
            skippedToday = 0
            saveStats()
        }
    }
}

func clock(_ seconds: Int) -> String {
    let s = max(seconds, 0)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
