import SwiftUI
import AppKit
import CryptoKit

final class DecodedImageCache {
    static let shared = DecodedImageCache()

    private let cache = NSCache<NSString, NSImage>()

    func cacheKey(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func image(for data: Data) -> NSImage? {
        let key = cacheKey(for: data) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }
}

struct CachedDataImageView: View {
    private enum LoadState {
        case idle
        case loading
        case loaded(NSImage)
        case unavailable
    }

    let data: Data?
    /// Include stable surrounding identity so view task resets cleanly on card switches.
    let viewID: String
    let availableSize: CGSize

    @State private var loadState: LoadState = .idle

    var body: some View {
        Group {
            switch loadState {
            case .loaded(let image):
                let size = displaySize(for: image)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            case .idle, .loading:
                if data == nil {
                    unavailablePlaceholder
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Loading image...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
            case .unavailable:
                unavailablePlaceholder
            }
        }
        .id(viewID)
        .task(id: viewID) {
            guard let data else {
                loadState = .unavailable
                return
            }
            loadState = .loading
            let image = await Task.detached(priority: .userInitiated) {
                DecodedImageCache.shared.image(for: data)
            }.value
            loadState = image.map(LoadState.loaded) ?? .unavailable
        }
    }

    private func displaySize(for image: NSImage) -> CGSize {
        let nw = image.size.width
        let nh = image.size.height
        guard nw > 0, nh > 0 else { return CGSize(width: nw, height: nh) }
        if nw <= availableSize.width && nh <= availableSize.height {
            return CGSize(width: nw, height: nh)
        }
        let scale = min(availableSize.width / nw, availableSize.height / nh)
        return CGSize(width: (nw * scale).rounded(), height: (nh * scale).rounded())
    }

    private var unavailablePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Image unavailable")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}
