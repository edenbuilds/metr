import AppKit
import SwiftUI
import MetrKit

/// Provider identity is carried by the provider's real supplied SVG mark, not
/// by a guessed SF Symbol. The SVGs are vendored from theSVG and bundled so
/// the dock stays offline, crisp, and deterministic at every scale.
struct ProviderLogo: View {
    let identity: ProviderIdentity
    var size: CGFloat = 15

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
        guard let url = Bundle.module.url(
            forResource: identity.id,
            withExtension: "svg",
            subdirectory: "ProviderLogos"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}
