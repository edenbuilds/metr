#!/usr/bin/env swift
// Renders metr's app icon and menu-bar template from the same geometry the
// app draws at runtime, so the mark can never drift between the two.
import AppKit

let bone = NSColor(calibratedRed: 0.965, green: 0.961, blue: 0.949, alpha: 1)
let charcoal = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.078, alpha: 1)

func vesselPath(in rect: NSRect, insetRatio: CGFloat) -> NSBezierPath {
    let w = rect.width, h = rect.height
    let r = w * 0.30
    let x0 = rect.minX + w * 0.06, x1 = rect.maxX - w * 0.06
    let path = NSBezierPath()
    // Flipped coordinates: NSBezierPath origin is bottom-left.
    path.move(to: NSPoint(x: x0, y: rect.maxY - h * 0.10))
    path.line(to: NSPoint(x: x0, y: rect.minY + r))
    path.curve(to: NSPoint(x: x0 + r, y: rect.minY),
               controlPoint1: NSPoint(x: x0, y: rect.minY), controlPoint2: NSPoint(x: x0, y: rect.minY))
    path.line(to: NSPoint(x: x1 - r, y: rect.minY))
    path.curve(to: NSPoint(x: x1, y: rect.minY + r),
               controlPoint1: NSPoint(x: x1, y: rect.minY), controlPoint2: NSPoint(x: x1, y: rect.minY))
    path.line(to: NSPoint(x: x1, y: rect.maxY - h * 0.10))
    _ = insetRatio
    return path
}

func waterPath(in rect: NSRect, level: CGFloat) -> NSBezierPath {
    let surfaceY = rect.minY + rect.height * 0.05 + rect.height * 0.86 * level
    let amp = rect.height * 0.028
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX, y: rect.minY))
    path.line(to: NSPoint(x: rect.minX, y: surfaceY))
    let steps = 40
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        path.line(to: NSPoint(x: rect.minX + rect.width * t,
                              y: surfaceY + sin(t * .pi * 2) * amp))
    }
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.close()
    return path
}

func interiorPath(in rect: NSRect) -> NSBezierPath {
    let w = rect.width
    let r = w * 0.26
    let x0 = rect.minX + w * 0.10, x1 = rect.maxX - w * 0.10
    let y0 = rect.minY + w * 0.04
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x0, y: rect.maxY - rect.height * 0.06))
    path.line(to: NSPoint(x: x0, y: y0 + r))
    path.curve(to: NSPoint(x: x0 + r, y: y0), controlPoint1: NSPoint(x: x0, y: y0), controlPoint2: NSPoint(x: x0, y: y0))
    path.line(to: NSPoint(x: x1 - r, y: y0))
    path.curve(to: NSPoint(x: x1, y: y0 + r), controlPoint1: NSPoint(x: x1, y: y0), controlPoint2: NSPoint(x: x1, y: y0))
    path.line(to: NSPoint(x: x1, y: rect.maxY - rect.height * 0.06))
    path.close()
    return path
}

func eyesPath(in rect: NSRect) -> NSBezierPath {
    let w = rect.width, h = rect.height
    let eyeY = rect.maxY - h * 0.33
    let spacing = w * 0.215
    let path = NSBezierPath()
    for cx in [rect.midX - spacing / 2, rect.midX + spacing / 2] {
        path.append(NSBezierPath(ovalIn: NSRect(x: cx - w * 0.0525, y: eyeY - w * 0.07,
                                                width: w * 0.105, height: w * 0.14)))
    }
    return path
}

/// Draws the mark. `template` renders a flat black glyph with no tile, for the menu bar.
func renderMark(size: CGFloat, template: Bool, level: CGFloat = 0.42) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let full = NSRect(x: 0, y: 0, width: size, height: size)
    let fg: NSColor = template ? .black : bone

    if !template {
        let tile = NSBezierPath(roundedRect: full, xRadius: size * 0.2237, yRadius: size * 0.2237)
        charcoal.setFill()
        tile.fill()
    }

    let inset = template ? size * 0.06 : size * 0.235
    let markRect = full.insetBy(dx: inset, dy: inset)

    // Water first, clipped to the vessel interior.
    ctx.saveGState()
    interiorPath(in: markRect).addClip()
    fg.withAlphaComponent(template ? 0.55 : 0.9).setFill()
    waterPath(in: markRect, level: level).fill()
    ctx.restoreGState()

    // Vessel outline.
    fg.setStroke()
    let outline = vesselPath(in: markRect, insetRatio: 0)
    outline.lineWidth = markRect.width * 0.078
    outline.lineCapStyle = .round
    outline.lineJoinStyle = .round
    outline.stroke()

    // Eyes punched out.
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    eyesPath(in: markRect).fill()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Branding/metr.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = CGFloat(size * scale)
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    writePNG(renderMark(size: px, template: false), to: iconset.appendingPathComponent(name))
}

// Menu-bar template glyph, 18pt at 1x/2x/3x.
let menubar = root.appendingPathComponent("Branding/menubar")
try? FileManager.default.createDirectory(at: menubar, withIntermediateDirectories: true)
for scale in [1, 2, 3] {
    let name = scale == 1 ? "metrTemplate.png" : "metrTemplate@\(scale)x.png"
    writePNG(renderMark(size: CGFloat(18 * scale), template: true), to: menubar.appendingPathComponent(name))
}

// A large flat mark for the README and the share page.
writePNG(renderMark(size: 1024, template: false), to: root.appendingPathComponent("Branding/metr-icon-1024.png"))
print("wrote icons")
