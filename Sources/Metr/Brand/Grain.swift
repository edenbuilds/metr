import AppKit
import SwiftUI

/// A fixed, tiling film-grain texture.
///
/// Generated once from a seeded generator and cached, so it costs one small
/// bitmap for the life of the process and nothing per frame. A `Canvas` that
/// redrew noise every frame would look the same and cost a great deal more.
enum Grain {

    static let tileSize = 128

    /// Deterministic so the texture never shimmers between redraws.
    private static var seed: UInt64 = 0x5EED_741D_E110

    private static func nextRandom() -> UInt64 {
        // xorshift64*, plenty for visual noise.
        seed ^= seed >> 12
        seed ^= seed << 25
        seed ^= seed >> 27
        return seed &* 2_685_821_657_736_338_717
    }

    /// A monochrome noise tile with alpha variation only, so it can be overlaid
    /// on any background in either appearance.
    static let tile: NSImage = {
        seed = 0x5EED_741D_E110
        let size = tileSize
        let bytesPerPixel = 4
        var pixels = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

        for index in 0..<(size * size) {
            let value = UInt8(nextRandom() % 256)
            let offset = index * bytesPerPixel
            pixels[offset] = value           // R
            pixels[offset + 1] = value       // G
            pixels[offset + 2] = value       // B
            // Sparse alpha keeps the grain fine rather than a flat grey wash.
            pixels[offset + 3] = value > 150 ? UInt8((Int(value) - 150) * 2) : 0
        }

        let image = NSImage(size: NSSize(width: size, height: size))
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: size, height: size,
                    bitsPerComponent: 8, bytesPerRow: size * bytesPerPixel,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  let cgImage = context.makeImage() else { return }
            image.lockFocus()
            NSGraphicsContext.current?.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            image.unlockFocus()
        }
        return image
    }()
}

/// Overlays the grain, tiled, at a whisper of opacity.
struct GrainOverlay: View {
    var opacity: Double = 0.024

    var body: some View {
        Image(nsImage: Grain.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
    }
}

/// A very faint ordered-dither wash, layered under the grain.
///
/// This is what gives the surface its "printed" quality rather than the flat
/// digital gradient a plain material has. Drawn as a static `Canvas` pass with
/// no per-frame work.
struct DitherWash: View {
    var tint: Color
    var opacity: Double = 0.018

    /// 4×4 Bayer matrix — the classic ordered-dither threshold map.
    private static let bayer: [[Double]] = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5]
    ].map { $0.map { $0 / 16.0 } }

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 3
            let columns = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    // Gradient runs top-to-bottom; the dither decides whether
                    // each cell is on, which is what makes the banding visible
                    // as texture rather than a smooth ramp.
                    let gradient = Double(row) / Double(max(1, rows))
                    let threshold = Self.bayer[row % 4][column % 4]
                    guard gradient > threshold else { continue }
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                                    width: cell - 1, height: cell - 1)),
                        with: .color(tint)
                    )
                }
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

/// The panel's full surface treatment: material, dither wash, grain, hairline.
struct PanelSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.panel

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thickMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
                    DitherWash(tint: Brand.charcoal)
                    GrainOverlay()
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
            )
    }
}

extension View {
    func panelSurface(cornerRadius: CGFloat = Theme.Radius.panel) -> some View {
        modifier(PanelSurface(cornerRadius: cornerRadius))
    }
}
