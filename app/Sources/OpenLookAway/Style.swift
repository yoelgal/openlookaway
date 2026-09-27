import AppKit
import SwiftUI

extension Color {
    static let brandPink = Color(red: 0.90, green: 0.31, blue: 0.82)
    static let brandOrange = Color(red: 0.97, green: 0.65, blue: 0.27)
    static let breakBlue = Color(red: 0.66, green: 0.85, blue: 1.0)
}

extension ShapeStyle where Self == LinearGradient {
    static var brand: LinearGradient {
        LinearGradient(colors: [.brandPink, .brandOrange], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The mascot: a gradient ball with closed, content eyes.
struct Mascot: View {
    enum Face { case happy, squeeze }
    var face = Face.happy

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / 64
            ZStack {
                Circle().fill(.brand)
                Path { p in
                    switch face {
                    case .happy:
                        for cx in [23.5, 40.5] {
                            p.addArc(center: CGPoint(x: cx * s, y: 31 * s), radius: 5.5 * s,
                                     startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                        }
                    case .squeeze:
                        p.move(to: CGPoint(x: 19 * s, y: 25 * s)); p.addLine(to: CGPoint(x: 27 * s, y: 30 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 35 * s))
                        p.move(to: CGPoint(x: 45 * s, y: 25 * s)); p.addLine(to: CGPoint(x: 37 * s, y: 30 * s)); p.addLine(to: CGPoint(x: 45 * s, y: 35 * s))
                    }
                }
                .stroke(Color(red: 0.29, green: 0.07, blue: 0.22), style: StrokeStyle(lineWidth: 3.6 * s, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Rounded gradient tile with a white symbol, like System Settings' sidebar icons.
struct Tile: View {
    let symbol: String
    var colors: [Color] = [.brandPink, .brandOrange]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
    }
}

/// Translucent capsule used on the break screen and the heads-up card.
struct GlassPill: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                if prominent { Capsule().fill(.brand) } else { Capsule().fill(.white.opacity(configuration.isPressed ? 0.24 : 0.12)) }
            }
            .foregroundStyle(.white)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

enum MenuBarIcon {
    /// Template image: mascot + countdown in a faint pill, so it tints with the menu bar.
    static func image(text: String?) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let label = NSAttributedString(string: text ?? "", attributes: [.font: font, .foregroundColor: NSColor.black])
        let h: CGFloat = 18, icon: CGFloat = 14, pad: CGFloat = 6
        let w = text == nil ? icon + 2 : pad + icon + 5 + ceil(label.size().width) + pad
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            if text != nil {
                NSColor.black.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            }
            let r = NSRect(x: text == nil ? 1 : pad, y: (h - icon) / 2, width: icon, height: icon)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: r).fill()
            // Knock the eyes out of the ball.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let s = icon / 64, eyes = NSBezierPath()
            for cx in [23.5, 40.5] {
                eyes.move(to: NSPoint(x: r.minX + (cx - 5.5) * s, y: r.minY + 33 * s))
                eyes.appendArc(withCenter: NSPoint(x: r.minX + cx * s, y: r.minY + 33 * s), radius: 5.5 * s, startAngle: 180, endAngle: 0, clockwise: true)
            }
            eyes.lineWidth = 5 * s
            eyes.lineCapStyle = .round
            eyes.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            label.draw(at: NSPoint(x: r.maxX + 5, y: (h - label.size().height) / 2))
            return true
        }
        img.isTemplate = true
        return img
    }
}
