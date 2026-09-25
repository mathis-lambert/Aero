import SwiftUI

/// A site's icon, or the given placeholder until one is known. Decorative: rows carry the site name.
struct FaviconView<Placeholder: View>: View {
    let cache: FaviconCache
    let key: FaviconKey?
    let size: CGFloat
    @ViewBuilder let placeholder: Placeholder

    var body: some View {
        Group {
            if let key, let image = cache.images[key] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * BrowserDesign.faviconCornerRatio))
            } else {
                placeholder
            }
        }
        .accessibilityHidden(true)
        .task(id: key) {
            if let key { await cache.load(key) }
        }
    }
}
