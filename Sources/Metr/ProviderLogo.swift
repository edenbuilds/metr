import AppKit
import SwiftUI
import MetrKit

/// Provider identity is carried by the provider's real supplied SVG mark, not
/// by a guessed SF Symbol. The SVGs are vendored from theSVG and bundled so
/// the dock stays offline, crisp, and deterministic at every scale.
struct ProviderLogo: View {
    let identity: ProviderIdentity

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: 15, height: 15)
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
