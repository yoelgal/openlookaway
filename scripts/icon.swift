// Cuts the generated icon art out of its background into a transparent macOS squircle.
// swift scripts/icon.swift <generated.png> <out-1024.png>
import AppKit

let args = CommandLine.arguments
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
let (w, h) = (src.pixelsWide, src.pixelsHigh)

// Bounding box of the tile = everything that isn't near-white background.
var (minX, minY, maxX, maxY) = (w, h, 0, 0)
for y in stride(from: 0, to: h, by: 2) {
    for x in stride(from: 0, to: w, by: 2) {
        let c = src.colorAt(x: x, y: y)!
        if c.redComponent + c.greenComponent + c.blueComponent < 2.7 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
// Trim a few px so no background fringe survives the mask.
let inset = 6
let crop = CGRect(x: minX + inset, y: minY + inset, width: maxX - minX - 2 * inset, height: maxY - minY - 2 * inset)
let tile = src.cgImage!.cropping(to: crop)!

let size = 1024, box = 824.0, pad = 100.0
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rect = CGRect(x: pad, y: pad, width: box, height: box)
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: box * 0.225, cornerHeight: box * 0.225, transform: nil))
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(tile, in: rect)
let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("bbox", crop)
