// Turns the Figma frame "App icon on blush" (Logo section, node 76:24) into the square, opaque iOS icon.
// Figma's export has rounded corners and a thin border, but iOS rounds icons itself and wants no
// transparency. So the frame's gradient (#FFEEEB at the top to white) fills the whole square, and the
// middle of the export (the sun on that gradient) is laid on top, leaving out the corners and border.
//
// Export the frame from Figma as a 1024 x 1024 PNG, then from the repo root:
//   swiftc -o /tmp/flatten-app-icon Tools/flatten-app-icon.swift
//   /tmp/flatten-app-icon ~/Downloads/app-icon-on-blush.png PillBox/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!
let figma = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let side = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let pink = CGColor(colorSpace: srgb, components: [1, 0.93333334, 0.92156863, 1])!
let white = CGColor(colorSpace: srgb, components: [1, 1, 1, 1])!
let gradient = CGGradient(colorsSpace: srgb, colors: [pink, white] as CFArray, locations: [0, 1])!
// Core Graphics puts y = 0 at the bottom, so the top of the icon is y = side.
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let full = CGRect(x: 0, y: 0, width: side, height: side)
ctx.addPath(CGPath(roundedRect: full.insetBy(dx: 16, dy: 16), cornerWidth: 400, cornerHeight: 400, transform: nil))
ctx.clip()
ctx.draw(figma, in: full)
let out = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil)
precondition(CGImageDestinationFinalize(dest))
print("wrote \(args[2])")
