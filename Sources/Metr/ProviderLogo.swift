import AppKit
import SwiftUI
import MetrKit

/// Provider identity is carried by the provider's real supplied SVG mark, not
/// by a guessed SF Symbol. The SVGs are vendored from theSVG and bundled so
/// the dock stays offline, crisp, and deterministic at every scale.
struct ProviderLogo: View {
    let identity: ProviderIdentity
    var size: CGFloat = 15

    private static var cache: [String: NSImage] = [:]

    private var assetID: String {
        switch identity.id {
        case "claude": return "anthropic"
        case "codex": return "openai"
        default: return identity.id
        }
    }

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary.opacity(0.88))
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func loadImage() -> NSImage? {
        if let cached = Self.cache[assetID] { return cached }
        let url = Bundle.module.url(
            forResource: assetID,
            withExtension: "svg",
            subdirectory: "ProviderLogos"
        ) ?? Bundle.module.url(
            forResource: assetID,
            withExtension: "svg"
        )
        guard let url, let image = NSImage(contentsOf: url) else {
            return nil
        }
        // SwiftUI can keep an SVG NSImage's vector representation blank on a
        // few macOS releases. Rasterise the already-bundled SVG once at a
        // generous scale, then let SwiftUI tint that stable representation.
        let canvas = NSSize(width: 96, height: 96)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 96,
            pixelsHigh: 96,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: canvas),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let rendered = NSImage(size: canvas)
        rendered.addRepresentation(bitmap)
        rendered.isTemplate = true
        Self.cache[assetID] = rendered
        return rendered
    }
}
