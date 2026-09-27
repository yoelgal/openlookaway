import AppKit
import CoreImage
import SwiftUI

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Full-screen break overlay on every display.
@MainActor
enum Overlay {
    private static var windows: [NSWindow] = []
    private static var escMonitor: Any?
    private static var lastEsc = Date.distantPast

    static func show(_ s: Scheduler) {
        hide()
        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: BreakView(s: s, backdrop: Backdrop.image(for: screen)))
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 53 else { return e }
            if Date.now.timeIntervalSince(lastEsc) < 1 { doubleEscape(s) } else { lastEsc = .now }
            return nil
        }
    }

    static func hide() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        let old = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            old.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { old.forEach { $0.orderOut(nil) } })
    }

    private static func doubleEscape(_ s: Scheduler) {
        let d = UserDefaults.standard
        if d.integer(forKey: Key.escAction) == 1, s.snoozesLeft > 0 { return s.snooze(minutes: 5) }
        if BreakView.canSkip(s) { s.skipNext() }
    }
}

/// Break background: the user's wallpaper blurred, a gradient, or their own image.
@MainActor
enum Backdrop {
    private static var cache: [String: NSImage] = [:]

    static func image(for screen: NSScreen) -> NSImage? {
        let d = UserDefaults.standard
        switch d.integer(forKey: Key.background) {
        case 1: return nil
        case 2:
            let path = d.string(forKey: Key.customImage) ?? ""
            if !path.isEmpty, let img = blurred(URL(fileURLWithPath: path), radius: 0) { return img }
            fallthrough
        default:
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), let img = blurred(url, radius: 60) { return img }
            return Bundle.main.url(forResource: "wall-blue", withExtension: "jpg").flatMap { blurred($0, radius: 60) }
        }
    }

    static func blurred(_ url: URL, radius: Double) -> NSImage? {
        let key = "\(url.path)#\(radius)"
        if let hit = cache[key] { return hit }
        guard var ci = CIImage(contentsOf: url) else { return nil }
        // Blur a small copy: faster and just as smooth.
        let scale = min(1, 1280 / ci.extent.width)
        ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = ci.extent
        if radius > 0 {
            ci = ci.clampedToExtent().applyingGaussianBlur(sigma: radius * scale * 2).cropped(to: extent)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.5, kCIInputBrightnessKey: -0.08])
        }
        guard let cg = CIContext().createCGImage(ci, from: extent) else { return nil }
        let img = NSImage(cgImage: cg, size: extent.size)
        cache[key] = img
        return img
    }
}

struct BreakView: View {
    let s: Scheduler
    let backdrop: NSImage?
    @AppStorage(Key.breakMode) private var mode = 0

    static let balancedDelay = 5

    static func canSkip(_ s: Scheduler) -> Bool {
        switch UserDefaults.standard.integer(forKey: Key.breakMode) {
        case 2: return false
        case 1: return s.breakElapsed >= balancedDelay
        default: return true
        }
    }

    var body: some View {
        ZStack {
            background
            TimelineView(.everyMinute) { ctx in
                Label(ctx.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.7)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 36)

            VStack(spacing: 14) {
                Text(s.title)
                    .font(.system(size: 44, weight: .bold))
                Text(s.message)
                    .font(.system(size: 17, weight: .medium))
                    .opacity(0.8)
                    .frame(maxWidth: 560)
                Capsule().fill(.white.opacity(0.3)).frame(width: 60, height: 2).padding(.vertical, 14)
                Text(clock(s.remaining))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.breakBlue)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: s.remaining)
            }
            .multilineTextAlignment(.center)
            .offset(y: -40)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    if mode != 2 {
                        Button { s.skipNext() } label: {
                            HStack(spacing: 6) {
                                if mode == 1 && s.breakElapsed < Self.balancedDelay {
                                    Circle().trim(from: 0, to: Double(s.breakElapsed) / Double(Self.balancedDelay))
                                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 12, height: 12)
                                        .animation(.linear(duration: 1), value: s.breakElapsed)
                                } else {
                                    Image(systemName: "chevron.forward.2")
                                }
                                Text("Skip Break")
                            }
                        }
                        .disabled(!Self.canSkip(s))
                    }
                    Button { System.lockScreen() } label: { Label("Lock Screen", systemImage: "lock") }
                }
                .buttonStyle(GlassPill())

                VStack(spacing: 5) {
                    Text(s.snoozesLeft == 1 ? "1 snooze left today" : "\(s.snoozesLeft) snoozes left today")
                    if mode != 2 {
                        HStack(spacing: 5) {
                            Text("Press")
                            Text("Esc").font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.4)))
                            Text(UserDefaults.standard.integer(forKey: Key.escAction) == 1 ? "twice to snooze 5 minutes" : "twice to skip the break")
                        }
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .opacity(0.55)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 64)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var background: some View {
        if let backdrop {
            Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill).ignoresSafeArea()
            Color.black.opacity(0.32).ignoresSafeArea()
        } else {
            ZStack {
                Blur()
                LinearGradient(colors: [Color(red: 0.16, green: 0.10, blue: 0.45), Color(red: 0.55, green: 0.18, blue: 0.55), Color(red: 0.95, green: 0.55, blue: 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .opacity(0.85)
            }
            .ignoresSafeArea()
        }
    }
}

struct Blur: NSViewRepresentable {
    var material = NSVisualEffectView.Material.fullScreenUI
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
