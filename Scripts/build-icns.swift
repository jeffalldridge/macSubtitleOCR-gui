#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: build-icns.swift <source.svg> <output.icns>\n".utf8))
    exit(64)
}
let srcSVG = URL(fileURLWithPath: CommandLine.arguments[1])
let outICNS = URL(fileURLWithPath: CommandLine.arguments[2])

guard let svg = NSImage(contentsOf: srcSVG) else {
    FileHandle.standardError.write(Data("Could not load SVG at \(srcSVG.path)\n".utf8))
    exit(1)
}

let iconsetDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("icon-build-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetDir) }

let bottomBlue = NSColor(srgbRed: 0.0,  green: 0.36921, blue: 0.74973, alpha: 1.0)
let topBlue    = NSColor(srgbRed: 0.18, green: 0.55,    blue: 0.92,    alpha: 1.0)

func render(size: Int, to url: URL) throws {
    let bm = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    bm.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bm)
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // Background gradient (top = lighter blue, bottom = spec blue, angle 90 = bottom->top)
    let gradient = NSGradient(starting: bottomBlue, ending: topBlue)!
    gradient.draw(in: rect, angle: 90)

    // Drop shadow under the bubble
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = max(1, CGFloat(size) / 30)
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) / 60)
    shadow.set()

    // Centered SVG at ~62% of canvas; inset = (1 - 0.62) / 2 = 0.19
    let inset = CGFloat(size) * 0.19
    let drawRect = NSRect(
        x: inset,
        y: inset,
        width:  CGFloat(size) - 2 * inset,
        height: CGFloat(size) - 2 * inset
    )
    svg.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bm.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Failed to produce PNG for size \(size)\n".utf8))
        exit(1)
    }
    try png.write(to: url)
}

let sizes: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for (name, px) in sizes {
    FileHandle.standardOutput.write(Data("  rendering \(name) (\(px)x\(px))\n".utf8))
    try render(size: px, to: iconsetDir.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetDir.path, "-o", outICNS.path]
try task.run()
task.waitUntilExit()

if task.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed (\(task.terminationStatus))\n".utf8))
    exit(2)
}
FileHandle.standardOutput.write(Data("==> Wrote \(outICNS.path)\n".utf8))
