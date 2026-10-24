import SwiftUI
import UIKit

protocol ImageLoading: Sendable {
    func image(for url: URL) async throws -> UIImage
    /// Synchronous memory-cache lookup so cached images render without a placeholder flash.
    func cachedImage(for url: URL) -> UIImage?
}

/// Thread-safe memory cache (NSCache is documented as thread-safe and evicts under memory pressure).
final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, UIImage>()

    init(totalCostLimit: Int = 128 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimit
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: Self.cost(of: image))
    }

    private static func cost(of image: UIImage) -> Int {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        return Int(width * height * 4)
    }
}

/// Loads images with memory caching and in-flight request de-duplication.
/// Downloading and decoding happen off the main thread.
actor ImageLoader: ImageLoading {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memoryCache: ImageMemoryCache
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    init(session: URLSession = .shared, memoryCache: ImageMemoryCache = ImageMemoryCache()) {
        self.session = session
        self.memoryCache = memoryCache
    }

    nonisolated func cachedImage(for url: URL) -> UIImage? {
        memoryCache.image(for: url)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = memoryCache.image(for: url) { return cached }
        if let existing = inFlight[url] { return try await existing.value }

        let session = self.session
        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                throw NetworkError.invalidResponse
            }
            // Force decoding now (off-main) so scrolling doesn't stall on first draw.
            return image.preparingForDisplay() ?? image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let image = try await task.value
        memoryCache.insert(image, for: url)
        return image
    }
}

extension EnvironmentValues {
    @Entry var imageLoader: any ImageLoading = ImageLoader.shared
}

/// Drop-in replacement for AsyncImage that goes through the caching `ImageLoader`.
struct CachedAsyncImage: View {
    let url: URL?

    @Environment(\.imageLoader) private var loader
    @State private var loaded: UIImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image = loaded ?? url.flatMap({ loader.cachedImage(for: $0) }) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail || url == nil {
                Image(systemName: "person.crop.square")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        loaded = nil
        didFail = false
        guard let url else { return }
        if let cached = loader.cachedImage(for: url) {
            loaded = cached
            return
        }
        do {
            loaded = try await loader.image(for: url)
        } catch {
            didFail = !ErrorMapper.isCancellation(error)
        }
    }
}
