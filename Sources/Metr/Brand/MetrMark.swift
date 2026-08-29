import SwiftUI
import MetrKit

/// The Metr mascot.
///
/// A rounded vessel with a tide line across it and two eyes above the water.
/// The water level *is* the usage level, and the eyes change with severity — so
/// the mark carries status by shape and height, not only by colour. That is the
/// same reason the rest of the app pairs every colour with a symbol and a word.
struct MetrMark: View {
    /// 0...1 water level.
    var level: Double = 0.42
    var severity: Severity = .nominal
    /// Nil renders the "we do not know yet" face.
    var isKnown: Bool = true
    var foreground: Color = Brand.bone
    var background: Color? = Brand.charcoal
    /// Animated wobble for the tide line.
    var phase: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let background {
                    RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                        .fill(background)
                }
                vessel(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func vessel(size: CGFloat) -> some View {
        let inset = size * 0.235
        let vesselSize = size - inset * 2

        return ZStack {
            // The vessel outline: a rounded "U" open at the top.
            VesselShape()
                .stroke(foreground, style: StrokeStyle(lineWidth: size * 0.078, lineCap: .round, lineJoin: .round))
                .frame(width: vesselSize, height: vesselSize)

            // Water, clipped to the vessel interior.
            TideShape(level: level, phase: phase)
                .fill(foreground.opacity(0.9))
                .frame(width: vesselSize, height: vesselSize)
                .clipShape(VesselInterior())
                .frame(width: vesselSize, height: vesselSize)

            EyesShape(severity: severity, isKnown: isKnown)
                .fill(foreground)
                .frame(width: vesselSize, height: vesselSize)
                .blendMode(.destinationOut)
                .compositingGroup()
        }
        .compositingGroup()
        .frame(width: vesselSize, height: vesselSize)
    }
}

// MARK: - Geometry

/// The vessel: a squared-off U with generous corner rounding.
struct VesselShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let radius = w * 0.30
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.06, y: rect.minY + h * 0.10))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.06, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.06 + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX + w * 0.06, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.06 - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - w * 0.06, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX - w * 0.06, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.06, y: rect.minY + h * 0.10))
        return path
    }
}

/// Fillable version of the vessel, used to clip the water.
struct VesselInterior: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let radius = w * 0.26
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.10, y: rect.minY + h * 0.06))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.10, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.10 + radius, y: rect.maxY - w * 0.04),
            control: CGPoint(x: rect.minX + w * 0.10, y: rect.maxY - w * 0.04)
        )
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.10 - radius, y: rect.maxY - w * 0.04))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - w * 0.10, y: rect.maxY - radius),
            control: CGPoint(x: rect.maxX - w * 0.10, y: rect.maxY - w * 0.04)
        )
        path.addLine(to: CGPoint(x: rect.maxX - w * 0.10, y: rect.minY + h * 0.06))
        path.closeSubpath()
        return path
    }
}

/// The tide line: a gentle sine that rises with `level`.
struct TideShape: Shape {
    var level: Double
    var phase: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set { level = newValue.first; phase = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(1, max(0, level))
        // Keep a sliver visible even at zero so the mark never looks broken.
        let surfaceY = rect.maxY - (rect.height * 0.86) * clamped - rect.height * 0.05
        let amplitude = rect.height * 0.028
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: surfaceY))
        let steps = 24
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let x = rect.minX + rect.width * t
            let y = surfaceY + sin(t * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Two eyes, punched out of the mark. Their shape carries the status:
/// round when clear, narrowed when watching, arched when near the limit,
/// and flat dashes when nothing is known yet.
struct EyesShape: Shape {
    var severity: Severity
    var isKnown: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let eyeY = rect.minY + h * 0.33
        let spacing = w * 0.215
        let centres = [
            CGPoint(x: rect.midX - spacing / 2, y: eyeY),
            CGPoint(x: rect.midX + spacing / 2, y: eyeY)
        ]
        var path = Path()

        guard isKnown else {
            // Unknown: short flat dashes.
            for centre in centres {
                path.addRoundedRect(
                    in: CGRect(x: centre.x - w * 0.045, y: centre.y - h * 0.014,
                               width: w * 0.09, height: h * 0.028),
                    cornerSize: CGSize(width: h * 0.014, height: h * 0.014)
                )
            }
            return path
        }

        switch severity {
        case .nominal:
            for centre in centres {
                path.addEllipse(in: CGRect(x: centre.x - w * 0.0525, y: centre.y - w * 0.07,
                                           width: w * 0.105, height: w * 0.14))
            }
        case .watch:
            // Narrowed: shorter ellipses, as if squinting.
            for centre in centres {
                path.addEllipse(in: CGRect(x: centre.x - w * 0.048, y: centre.y - w * 0.032,
                                           width: w * 0.096, height: w * 0.064))
            }
        case .critical:
            // Arched, worried brows.
            for (index, centre) in centres.enumerated() {
                let lean = index == 0 ? 1.0 : -1.0
                var arc = Path()
                arc.move(to: CGPoint(x: centre.x - w * 0.05, y: centre.y + w * 0.02 * lean))
                arc.addQuadCurve(
                    to: CGPoint(x: centre.x + w * 0.05, y: centre.y - w * 0.02 * lean),
                    control: CGPoint(x: centre.x, y: centre.y - w * 0.055)
                )
                path.addPath(arc.strokedPath(StrokeStyle(lineWidth: w * 0.032, lineCap: .round)))
            }
        }
        return path
    }
}

// MARK: - Brand tokens

/// The palette. Warm, low-chroma, and deliberately small.
enum Brand {
    static let charcoal = Color(red: 0.078, green: 0.078, blue: 0.078)   // #141414
    static let bone = Color(red: 0.965, green: 0.961, blue: 0.949)       // #F6F5F2
    static let warmGray = Color(red: 0.898, green: 0.890, blue: 0.874)   // #E5E3DF
    static let olive = Color(red: 0.545, green: 0.690, blue: 0.255)      // signal green, used sparingly
    static let burntOrange = Color(red: 0.878, green: 0.478, blue: 0.228) // #E07A3A
    static let deepRed = Color(red: 0.780, green: 0.286, blue: 0.243)    // #C7493E

    static let name = "metr"
    static let tagline = "Your AI, metered."

    static func providerColor(for identity: ProviderIdentity) -> Color {
        Theme.tint(identity.tintName)
    }

    /// Status colours drawn from the brand palette rather than the stock
    /// system traffic-light greens and reds, which read as generic.
    static func statusColor(for severity: Severity) -> Color {
        switch severity {
        case .nominal: return olive
        case .watch: return burntOrange
        case .critical: return deepRed
        }
    }
}
