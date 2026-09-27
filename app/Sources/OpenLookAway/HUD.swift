import AppKit
import SwiftUI

/// Floating, non-activating panels: the heads-up card, the cursor countdown, and wellness nudges.
@MainActor
enum HUD {
    enum Nudge { case posture, blink }

    private static var card: NSPanel?
    private static var follower: NSPanel?
    private static var followTimer: Timer?
    private static var nudgePanel: NSPanel?
    private static var dismissWork: DispatchWorkItem?

    // MARK: Heads-up card

    static func headsUp(_ s: Scheduler) {
        let visible = Double(UserDefaults.standard.integer(forKey: Key.headsUpVisible))
        let lead = UserDefaults.standard.integer(forKey: Key.headsUpLead)
        let line = Scheduler.headsUpLines.randomElement()!
        card = present(HeadsUpCard(s: s, lead: lead, line: line), replacing: card, at: .top)
        dismissWork?.cancel()
        let work = DispatchWorkItem { card = fade(card) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(visible, 3), execute: work)
    }

    /// Short message in the heads-up spot (used for the first-launch hello).
    static func toast(_ text: String) {
        card = present(Card { HStack(spacing: 10) { Mascot().frame(width: 22); Text(text).font(.system(size: 13, weight: .semibold)) } },
                       replacing: card, at: .top)
        let work = DispatchWorkItem { card = fade(card) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    // MARK: Floating countdown

    static func floatingCountdown(_ s: Scheduler) {
        guard follower == nil else { return }
        card = fade(card)
        let p = makePanel(FollowerPill(s: s))
        follower = p
        let move = {
            let m = NSEvent.mouseLocation
            p.setFrameOrigin(NSPoint(x: m.x + 18, y: m.y - p.frame.height - 14))
        }
        move()
        show(p)
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in MainActor.assumeIsolated { move() } }
    }

    // MARK: Nudges

    static func nudge(_ kind: Nudge) {
        guard card == nil, follower == nil else { return }
        nudgePanel = fade(nudgePanel)
        let p = makePanel(NudgeView(kind: kind))
        if let f = (NSScreen.main ?? NSScreen.screens.first)?.frame {
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.midY - p.frame.height / 2 + f.height * 0.18))
        }
        show(p)
        nudgePanel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { if nudgePanel === p { nudgePanel = fade(p) } }
    }

    static func hideAlerts() {
        dismissWork?.cancel()
        card = fade(card)
        followTimer?.invalidate()
        followTimer = nil
        follower = fade(follower)
    }

    // MARK: Plumbing

    private enum Spot { case top }

    private static func present<V: View>(_ view: V, replacing old: NSPanel?, at spot: Spot) -> NSPanel {
        _ = fade(old)
        let p = makePanel(view)
        if let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let w = p.frame.width
            let x: CGFloat = switch UserDefaults.standard.integer(forKey: Key.alertPosition) {
            case 0: vf.minX + 12
            case 2: vf.maxX - w - 12
            default: vf.midX - w / 2
            }
            p.setFrameOrigin(NSPoint(x: x, y: vf.maxY - p.frame.height - 8))
        }
        show(p)
        return p
    }

    private static func makePanel<V: View>(_ view: V) -> NSPanel {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.contentView = host
        return p
    }

    private static func show(_ p: NSPanel) {
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
    }

    /// Fades a panel out and returns nil, so callers can write `x = fade(x)`.
    @discardableResult
    private static func fade(_ p: NSPanel?) -> NSPanel? {
        guard let p else { return nil }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                             completionHandler: { p.orderOut(nil) })
        return nil
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
            .background(Blur(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 18)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .padding(20)
            .foregroundStyle(.white)
    }
}

struct HeadsUpCard: View {
    let s: Scheduler
    let lead: Int
    let line: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.brand).padding(4)
                        Circle().trim(from: 0, to: Double(max(s.remaining, 0)) / Double(max(lead, 1)))
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: s.remaining)
                        Image(systemName: "clock").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(clock(s.remaining)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                        Text(line).font(.system(size: 12)).opacity(0.75)
                    }
                }
                HStack(spacing: 6) {
                    Button("Start this break now") { s.startBreak() }.fixedSize()
                    ForEach([1, 5, 15], id: \.self) { m in
                        Button("+\(m)m") { s.snooze(minutes: m) }.disabled(s.snoozesLeft == 0)
                    }
                }
                .buttonStyle(GlassPill())
                .lineLimit(1)
            }
            .frame(width: 370, alignment: .leading)
        }
    }
}

struct FollowerPill: View {
    let s: Scheduler
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6).fill(.brand).frame(width: 22, height: 22)
                .overlay(Image(nsImage: MenuBarIcon.image(text: nil)).foregroundStyle(.white))
            Text("Starting break in \(String(format: "%02d", max(s.remaining, 0)))")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .background(Blur(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
        .foregroundStyle(.white)
        .padding(10)
    }
}

/// Posture: the ball pops in, stretches into a pill while an arrow rises. Blink: the face squeezes, then relaxes.
struct NudgeView: View {
    let kind: HUD.Nudge
    @State private var shown = false
    @State private var stretched = false
    @State private var relaxed = false

    var body: some View {
        ZStack {
            Capsule()
                .fill(.black.opacity(0.35))
                .frame(width: 76, height: stretched ? 150 : 76)
            Group {
                switch kind {
                case .posture:
                    Circle().fill(.brand).frame(width: 64, height: 64)
                        .overlay(Image(systemName: "arrow.up").font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Color(red: 0.29, green: 0.07, blue: 0.22)))
                        .offset(y: stretched ? -37 : 0)
                case .blink:
                    Mascot(face: relaxed ? .happy : .squeeze).frame(width: 64, height: 64)
                }
            }
        }
        .frame(width: 90, height: 170)
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .task {
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { shown = true }
            try? await Task.sleep(for: .milliseconds(600))
            if kind == .posture {
                withAnimation(.spring(duration: 0.7, bounce: 0.2)) { stretched = true }
                try? await Task.sleep(for: .milliseconds(1300))
                withAnimation(.easeInOut(duration: 0.4)) { stretched = false }
            } else {
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeInOut(duration: 0.25)) { relaxed = true }
                try? await Task.sleep(for: .milliseconds(1100))
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeIn(duration: 0.35)) { shown = false }
        }
    }
}
