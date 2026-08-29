import AppKit
import SwiftUI

/// The supplied cat mark is the personality layer for metr. The two bundled
/// crops are intentional: the tile remains legible in both menu-bar themes.
struct MetrCatLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }

    private var image: NSImage {
        let name = colorScheme == .dark ? "cat-dark" : "cat-light"
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Branding"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: size, height: size))
    }
}
