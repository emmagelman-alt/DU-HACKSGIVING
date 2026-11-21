// Draws the sample pharmacy label images and the app icon into PillBox/Assets.xcassets.
// Run from the repo root:
//   swiftc -o /tmp/make-assets Tools/make-assets/main.swift PillBox/Demo/SampleLabels.swift && /tmp/make-assets
import AppKit

let root = FileManager.default.currentDirectoryPath + "/PillBox/Assets.xcassets"

func png(width: Int, height: Int, draw: (CGRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Flip so y grows downward like a page.
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    NSAttributedString(string: s, attributes: attrs).draw(at: p)
}

func writeImageSet(name: String, data: Data) {
    let dir = "\(root)/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try! data.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    let json = """
    {
      "images" : [ { "filename" : "\(name).png", "idiom" : "universal" } ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try! json.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
}

for label in SampleLabel.all {
    let isCorner = label.pharmacy.hasPrefix("CORNER")
    let brand = isCorner ? NSColor(red: 0.75, green: 0.16, blue: 0.20, alpha: 1) : NSColor(red: 0.05, green: 0.45, blue: 0.52, alpha: 1)
    let data = png(width: 1400, height: 860) { r in
        NSColor(white: 0.93, alpha: 1).setFill(); r.fill()
        let card = NSBezierPath(roundedRect: r.insetBy(dx: 24, dy: 24), xRadius: 28, yRadius: 28)
        NSColor.white.setFill(); card.fill()
        let header = NSBezierPath(roundedRect: CGRect(x: 24, y: 24, width: 1352, height: 150), xRadius: 28, yRadius: 28)
        brand.setFill(); header.fill()
        NSRect(x: 24, y: 120, width: 1352, height: 54).fill()
        text(label.pharmacy, at: CGPoint(x: 70, y: 46), size: 54, weight: .heavy, color: .white)
        text(label.lines[0], at: CGPoint(x: 72, y: 116), size: 28, weight: .medium, color: NSColor.white.withAlphaComponent(0.9))

        var y: CGFloat = 200
        let l = label.lines
        text(l[1], at: CGPoint(x: 70, y: y), size: 32, weight: .medium); y += 52
        text(l[2], at: CGPoint(x: 70, y: y), size: 36, weight: .bold); y += 64
        text(l[3], at: CGPoint(x: 70, y: y), size: 52, weight: .heavy); y += 80
        text(l[4], at: CGPoint(x: 70, y: y), size: 40, weight: .bold); y += 54
        text(l[5], at: CGPoint(x: 70, y: y), size: 40, weight: .bold); y += 72
        NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 70, y: y - 14, width: 1260, height: 3).fill()
        text(l[6], at: CGPoint(x: 70, y: y), size: 32, weight: .medium); y += 50
        text(l[7], at: CGPoint(x: 70, y: y), size: 32, weight: .medium)
        text(l[8], at: CGPoint(x: 820, y: y - 50), size: 36, weight: .heavy, color: NSColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1))
        // What the pill looks like, printed small at the bottom as many pharmacies do.
        if l.count > 9 { text(l[9], at: CGPoint(x: 70, y: y + 58), size: 30, weight: .semibold, color: NSColor(white: 0.25, alpha: 1)) }
    }
    writeImageSet(name: label.asset, data: data)
    // Also save loose copies for adding to the simulator's photo library.
    try? FileManager.default.createDirectory(atPath: "design/sample-labels", withIntermediateDirectories: true)
    try! data.write(to: URL(fileURLWithPath: "design/sample-labels/\(label.asset).png"))
}

// App icon: a teal tile with a 2 x 2 pill box and a check mark.
let icon = png(width: 1024, height: 1024) { r in
    let g = NSGradient(starting: NSColor(red: 0.10, green: 0.62, blue: 0.66, alpha: 1), ending: NSColor(red: 0.03, green: 0.36, blue: 0.45, alpha: 1))!
    g.draw(in: r, angle: -90)
    let box = CGRect(x: 192, y: 232, width: 640, height: 560)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: box, xRadius: 90, yRadius: 90).fill()
    let colors: [NSColor] = [NSColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1), NSColor(red: 0.20, green: 0.62, blue: 0.95, alpha: 1),
                             NSColor(red: 0.62, green: 0.38, blue: 0.90, alpha: 1), NSColor(red: 0.25, green: 0.30, blue: 0.62, alpha: 1)]
    for i in 0..<4 {
        let cell = CGRect(x: 232 + CGFloat(i % 2) * 290, y: 272 + CGFloat(i / 2) * 250, width: 270, height: 230)
        colors[i].withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: cell, xRadius: 50, yRadius: 50).fill()
        colors[i].setFill()
        NSBezierPath(roundedRect: CGRect(x: cell.midX - 70, y: cell.midY - 30, width: 140, height: 60), xRadius: 30, yRadius: 30).fill()
    }
}
let iconDir = "\(root)/AppIcon.appiconset"
try! icon.write(to: URL(fileURLWithPath: "\(iconDir)/AppIcon.png"))
try! """
{
  "images" : [ { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
""".write(toFile: "\(iconDir)/Contents.json", atomically: true, encoding: .utf8)
print("Wrote \(SampleLabel.all.count) labels and the app icon.")
