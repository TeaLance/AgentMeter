#!/usr/bin/env swift
// Generate a macOS-native AppIcon.icns from a square source image.
//
// Takes the full-bleed artwork and renders it the way macOS expects an app
// icon to look: a rounded "squircle" tile, slightly inset from the canvas,
// with a soft contact shadow — at every size iconutil needs. The source art
// keeps its own internal margin, so we only round the corners and add a touch
// of breathing room rather than re-cropping it.
//
// Usage: swift Scripts/make-icns.swift <source.png> <out.icns>
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: make-icns.swift <source-image> <out.icns>\n".data(using: .utf8)!)
    exit(2)
}
let srcPath = args[1]
let outICNS = args[2]

guard let srcSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil),
      let src = CGImageSourceCreateImageAtIndex(srcSource, 0, nil) else {
    FileHandle.standardError.write("error: cannot read source image at \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}

// Body fills 90% of the canvas (5% margin each side); corner radius follows
// Apple's ~0.2237 keyline ratio relative to the body.
let bodyRatio: CGFloat = 0.90
let radiusRatio: CGFloat = 0.2237

func renderIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil,
                        width: pixels, height: pixels,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    let body = size * bodyRatio
    let origin = (size - body) / 2.0
    let bodyRect = CGRect(x: origin, y: origin, width: body, height: body)
    let radius = body * radiusRatio
    let path = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft contact shadow so the tile sits naturally, like native icons.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.022,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to the rounded tile and draw the artwork.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(src, in: bodyRect)
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// Build a temporary .iconset, then hand it to iconutil.
let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AgentMeter-\(ProcessInfo.processInfo.processIdentifier).iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]
for v in variants {
    writePNG(renderIcon(pixels: v.px), to: "\(iconset)/\(v.name).png")
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", outICNS]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(atPath: iconset)

if task.terminationStatus == 0 {
    print("Wrote \(outICNS)")
} else {
    FileHandle.standardError.write("error: iconutil failed\n".data(using: .utf8)!)
    exit(task.terminationStatus)
}
