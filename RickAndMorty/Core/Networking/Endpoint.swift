import Foundation

/// Describes a request relative to the API base URL.
struct Endpoint: Sendable, Equatable {
    let path: String
    var queryItems: [URLQueryItem] = []

    func url(relativeTo baseURL: URL) -> URL? {
        let url = baseURL.appendingPathComponent(path)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}

extension Endpoint {
    static func characters(page: Int, query: CharacterQuery) -> Endpoint {
        var items = [URLQueryItem(name: "page", value: String(page))]
        if !query.trimmedName.isEmpty {
            items.append(URLQueryItem(name: "name", value: query.trimmedName))
        }
        if let status = query.status {
            items.append(URLQueryItem(name: "status", value: status.apiValue))
        }
        return Endpoint(path: "character", queryItems: items)
    }

    /// The API accepts a comma separated list: /episode/1,2,3
    static func episodes(ids: [Int]) -> Endpoint {
        Endpoint(path: "episode/" + ids.map(String.init).joined(separator: ","))
    }
}
