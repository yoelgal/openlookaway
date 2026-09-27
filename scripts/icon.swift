// Renders the app icon: swift scripts/icon.swift out.png
import AppKit

let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let inset = 100.0, rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.30, green: 0.27, blue: 0.85, alpha: 1), NSColor(red: 0.12, green: 0.70, blue: 0.68, alpha: 1)])!
        .draw(in: shape, angle: -60)
    let cfg = NSImage.SymbolConfiguration(pointSize: 430, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    let eye = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    eye.draw(in: NSRect(x: (size - eye.size.width) / 2, y: (size - eye.size.height) / 2, width: eye.size.width, height: eye.size.height))
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
