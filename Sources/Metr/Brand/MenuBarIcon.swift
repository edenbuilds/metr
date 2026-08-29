import AppKit
import MetrKit

/// Renders the Metr mark as a menu-bar template image.
///
/// Template images are tinted by AppKit to match the menu bar, so the glyph is
/// drawn in flat black with alpha only. The water level is encoded as *fill*,
/// which survives that tinting — a colour-coded menu-bar icon would not.
enum MenuBarIcon {

    private static let pointSize: CGFloat = 18
    private static var cache: [String: NSImage] = [:]

    static func image(level: Double, severity: Severity, isKnown: Bool) -> NSImage {
        // Quantise the level so we redraw at most 20 distinct images rather than
        // once per refresh.
        let bucket = Int((min(1, max(0, level)) * 20).rounded())
        let key = "\(bucket)|\(severity.rawValue)|\(isKnown)"
        if let cached = cache[key] { return cached }

        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1.2, dy: 1.2)
        let black = NSColor.black

        // Water fill, clipped to the vessel interior.
        NSGraphicsContext.saveGraphicsState()
        interior(in: rect).addClip()
        black.withAlphaComponent(isKnown ? 0.55 : 0.22).setFill()
        water(in: rect, level: isKnown ? CGFloat(min(1, max(0, level))) : 0.12).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Vessel outline.
        black.setStroke()
        let outline = vessel(in: rect)
        outline.lineWidth = rect.width * 0.11
        outline.lineCapStyle = .round
        outline.lineJoinStyle = .round
        outline.stroke()

        // Eyes punched out, so the glyph keeps its face even at 18pt.
        NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
        eyes(in: rect, severity: severity, isKnown: isKnown).fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.normal)

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "metr"
        cache[key] = image
        return image
    }

    // MARK: Geometry (mirrors MetrMark, in AppKit's bottom-left origin)

    private static func vessel(in rect: NSRect) -> NSBezierPath {
        let w = rect.width, h = rect.height
        let r = w * 0.30
        let x0 = rect.minX + w * 0.08, x1 = rect.maxX - w * 0.08
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x0, y: rect.maxY - h * 0.06))
        path.line(to: NSPoint(x: x0, y: rect.minY + r))
        path.curve(to: NSPoint(x: x0 + r, y: rect.minY),
                   controlPoint1: NSPoint(x: x0, y: rect.minY), controlPoint2: NSPoint(x: x0, y: rect.minY))
        path.line(to: NSPoint(x: x1 - r, y: rect.minY))
        path.curve(to: NSPoint(x: x1, y: rect.minY + r),
                   controlPoint1: NSPoint(x: x1, y: rect.minY), controlPoint2: NSPoint(x: x1, y: rect.minY))
        path.line(to: NSPoint(x: x1, y: rect.maxY - h * 0.06))
        return path
    }

    private static func interior(in rect: NSRect) -> NSBezierPath {
        let w = rect.width
        let r = w * 0.25
        let x0 = rect.minX + w * 0.13, x1 = rect.maxX - w * 0.13
        let y0 = rect.minY + w * 0.05
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x0, y: rect.maxY))
        path.line(to: NSPoint(x: x0, y: y0 + r))
        path.curve(to: NSPoint(x: x0 + r, y: y0), controlPoint1: NSPoint(x: x0, y: y0), controlPoint2: NSPoint(x: x0, y: y0))
        path.line(to: NSPoint(x: x1 - r, y: y0))
        path.curve(to: NSPoint(x: x1, y: y0 + r), controlPoint1: NSPoint(x: x1, y: y0), controlPoint2: NSPoint(x: x1, y: y0))
        path.line(to: NSPoint(x: x1, y: rect.maxY))
        path.close()
        return path
    }

    private static func water(in rect: NSRect, level: CGFloat) -> NSBezierPath {
        let surfaceY = rect.minY + rect.height * 0.06 + rect.height * 0.80 * level
        return NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY,
                                         width: rect.width, height: surfaceY - rect.minY))
    }

    private static func eyes(in rect: NSRect, severity: Severity, isKnown: Bool) -> NSBezierPath {
        let w = rect.width, h = rect.height
        let eyeY = rect.maxY - h * 0.34
        let spacing = w * 0.30
        let path = NSBezierPath()
        for cx in [rect.midX - spacing / 2, rect.midX + spacing / 2] {
            guard isKnown else {
                path.append(NSBezierPath(rect: NSRect(x: cx - w * 0.07, y: eyeY - h * 0.018,
                                                      width: w * 0.14, height: h * 0.036)))
                continue
            }
            let height: CGFloat = severity == .watch ? w * 0.11 : w * 0.17
            path.append(NSBezierPath(ovalIn: NSRect(x: cx - w * 0.065, y: eyeY - height / 2,
                                                    width: w * 0.13, height: height)))
        }
        return path
    }
}
