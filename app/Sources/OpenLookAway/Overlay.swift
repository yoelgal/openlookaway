import AppKit
import SwiftUI

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Full-screen break overlay on every display.
@MainActor
enum Overlay {
    private static var windows: [NSWindow] = []

    static func show(_ s: Scheduler) {
        hide()
        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: BreakView(s: s))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    static func hide() {
        let old = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            old.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { old.forEach { $0.orderOut(nil) } })
    }
}

struct BreakView: View {
    let s: Scheduler
    @AppStorage(Key.allowSkip) private var allowSkip = true

    var body: some View {
        ZStack {
            Blur().ignoresSafeArea()
            LinearGradient(colors: [.indigo.opacity(0.55), .teal.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 28) {
                Image(systemName: s.isLongBreak ? "figure.walk" : "eye")
                    .font(.system(size: 44, weight: .light))
                Text(s.isLongBreak ? "Time for a longer break" : "Look away")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                Text(s.message)
                    .font(.title2)
                    .opacity(0.85)
                Text(clock(s.remaining))
                    .font(.system(size: 96, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: s.remaining)
                HStack(spacing: 12) {
                    Button("+1 min") { s.snooze(minutes: 1) }
                    Button("+5 min") { s.snooze(minutes: 5) }
                    if allowSkip {
                        Button("Skip") { s.skipNext() }.keyboardShortcut(.escape, modifiers: [])
                    }
                }
                .buttonStyle(Pill())
                .padding(.top, 12)
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
    }
}

struct Pill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.white.opacity(configuration.isPressed ? 0.3 : 0.16), in: Capsule())
            .contentShape(Capsule())
    }
}

struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Small floating card in the top-right corner: pre-break heads-up and wellness nudges.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var isHeadsUp = false
    private static var dismissWork: DispatchWorkItem?

    static func headsUp(_ s: Scheduler) {
        present(AnyView(HeadsUpView(s: s)), autoHide: nil)
        isHeadsUp = true
    }

    static func remind(_ text: String, symbol: String) {
        guard !isHeadsUp else { return }
        present(AnyView(Card {
            Label(text, systemImage: symbol).font(.body.weight(.medium))
        }), autoHide: 6)
    }

    static func hideHeadsUp() { if isHeadsUp { hide() } }

    static func hide() {
        dismissWork?.cancel()
        isHeadsUp = false
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 },
                                             completionHandler: { p.orderOut(nil) })
    }

    private static func present(_ view: AnyView, autoHide: Double?) {
        hide()
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.contentView = host
        if let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 12))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        panel = p
        if let t = autoHide {
            let work = DispatchWorkItem { hide() }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 260, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
            .padding(6)
    }
}

private struct HeadsUpView: View {
    let s: Scheduler
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Break in \(max(s.remaining, 0))s", systemImage: "eye")
                    .font(.headline)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Button("Start now") { s.startBreak() }.buttonStyle(.borderedProminent)
                    Button("+1m") { s.snooze(minutes: 1) }
                    Button("+5m") { s.snooze(minutes: 5) }
                    Button("Skip") { s.skipNext() }
                }
                .controlSize(.small)
            }
        }
    }
}
