import SwiftUI

/// The window that drops down from the menu bar item.
struct MenuPanel: View {
    let s: Scheduler
    let updater: Updater
    @State var tab = 0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Picker("", selection: $tab) {
                    Text("Now").tag(0)
                    Text("Stats").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
                HStack {
                    Spacer()
                    Button {
                        closePanel()
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                    } label: { Image(systemName: "gearshape.fill").font(.system(size: 14)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(",")
                }
            }

            if tab == 0 { now } else { StatsView(stats: s.stats) }

            HStack {
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).keyboardShortcut("q")
                Spacer()
                if let v = updater.available {
                    Button(updater.installing ? "Updating…" : "Update to \(v)") { updater.install() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandPink)
                        .disabled(updater.installing)
                } else {
                    Text("v\(updater.current)")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
    }

    private var now: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(.primary.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [.brandPink, .brandOrange, .brandPink], center: .center),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 2) {
                    if s.phase == .onBreak {
                        Text("On a break").font(.system(size: 18, weight: .semibold))
                    } else {
                        Text(clock(s.remaining)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        Text(s.isPaused || s.autoPauseReason != nil ? "paused" : "until your next break")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 140, height: 140)
            .opacity(s.isPaused || s.autoPauseReason != nil ? 0.5 : 1)

            if s.isPaused || s.autoPauseReason != nil {
                Text(s.status).font(.system(size: 12)).foregroundStyle(.secondary)
            }

            Button {
                closePanel()
                s.startBreak()
            } label: { Text("Take a break now").frame(maxWidth: .infinity) }
            .buttonStyle(GlassPill(prominent: true))

            HStack(spacing: 8) {
                if s.isPaused {
                    Button { s.resume() } label: { Text("Resume").frame(maxWidth: .infinity) }
                } else {
                    Menu {
                        Button("30 minutes") { s.pause(minutes: 30) }
                        Button("1 hour") { s.pause(minutes: 60) }
                        Button("2 hours") { s.pause(minutes: 120) }
                        Divider()
                        Button("Until I resume") { s.pause(minutes: nil) }
                    } label: { Text("Pause") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.primary.opacity(0.08), in: Capsule())
                }
                Button { s.skipNext() } label: { Text("Skip next").frame(maxWidth: .infinity) }
            }
            .buttonStyle(Secondary())
        }
    }

    private var progress: Double {
        guard s.phase == .working, s.workSeconds > 0 else { return 1 }
        return Double(max(s.remaining, 0)) / Double(s.workSeconds)
    }

    /// MenuBarExtra has no dismiss API; close its window directly.
    private func closePanel() {
        NSApp.windows.first { $0.className.contains("MenuBarExtra") && $0.isVisible }?.close()
    }
}

private struct Secondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.vertical, 7)
            .background(.primary.opacity(configuration.isPressed ? 0.16 : 0.08), in: Capsule())
            .contentShape(Capsule())
    }
}

struct StatsView: View {
    let stats: DayStats

    var body: some View {
        VStack(spacing: 14) {
            Text("Today's Screen Score").font(.system(size: 13, weight: .semibold))
            ZStack(alignment: .bottom) {
                Gauge(fraction: 1).stroke(.primary.opacity(0.1), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Gauge(fraction: Double(stats.score) / 100)
                    .stroke(LinearGradient(colors: [.brandPink, .brandOrange], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Text("\(stats.score)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 150, height: 80)
            Text(caption).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Section(title: "Breaks", symbol: "eye.fill") {
                Row(color: .brandPink, label: "Breaks taken", value: "\(stats.taken)", detail: duration(stats.takenSeconds))
                Row(color: .brandPink, label: "Natural breaks", value: "\(stats.natural)", detail: duration(stats.naturalSeconds))
                Row(color: .brandPink, label: "Skipped / snoozed", value: "\(stats.skipped + stats.snoozed)", detail: nil)
            }
            Section(title: "Screen time", symbol: "bolt.fill") {
                Row(color: .brandOrange, label: "Total screen time", value: duration(stats.screenSeconds), detail: nil)
                Row(color: .brandOrange, label: "Longest stretch", value: duration(stats.longestStretch), detail: nil)
            }
        }
    }

    private var caption: String {
        switch stats.score {
        case 90...: "Great pacing today. Keep it up."
        case 70..<90: "Pretty good. Take the next one."
        case 50..<70: "A few too many skips today."
        default: "Your eyes could really use a break."
        }
    }

    private struct Gauge: Shape {
        var fraction: Double
        func path(in r: CGRect) -> Path {
            Path { p in
                p.addArc(center: CGPoint(x: r.midX, y: r.maxY), radius: r.width / 2 - 5,
                         startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fraction), clockwise: false)
            }
        }
    }

    private struct Section<Content: View>: View {
        let title: String
        let symbol: String
        @ViewBuilder var content: Content
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Tile(symbol: symbol, size: 20)
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private struct Row: View {
        let color: Color
        let label: String
        let value: String
        let detail: String?
        var body: some View {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                Spacer()
                Text(value).monospacedDigit()
                if let detail { Text(detail).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing) }
            }
            .font(.system(size: 12))
        }
    }
}
