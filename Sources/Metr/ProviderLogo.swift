import AppKit
import SwiftUI
import MetrKit

/// Provider identity is carried by the provider's real supplied SVG mark, not
/// by a guessed SF Symbol. The SVGs are vendored from theSVG and bundled so
/// the dock stays offline, crisp, and deterministic at every scale.
struct ProviderLogo: View {
    let identity: ProviderIdentity
    var size: CGFloat = 15

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
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
        .task(id: identity.id) {
            image = loadImage()
        }
    }

    private func loadImage() -> NSImage? {
        guard let url = Bundle.module.url(
            forResource: identity.id,
            withExtension: "svg",
            subdirectory: "ProviderLogos"
        ), let data = try? Data(contentsOf: url), let image = NSImage(data: data) else {
            return nil
        }
        // SVGs can arrive without an intrinsic point size. Giving AppKit a
        // stable representation size prevents a blank or 1-point mark while
        // SwiftUI is resolving the bundled resource asynchronously.
        image.size = NSSize(width: 24, height: 24)
        image.isTemplate = true
        return image
    }
}
