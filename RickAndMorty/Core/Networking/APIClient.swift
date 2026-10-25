import Foundation

enum AppConfiguration {
    static let apiBaseURL: URL = {
        if let urlString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String {
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) {
                return url
            }
        }
        #if DEBUG
        return URL(string: "https://rickandmortyapi.com/api")!
        #else
        fatalError("API_BASE_URL is not set or invalid in Info.plist")
        #endif
    }()
}

/// Abstraction over the network so repositories can be tested with mocks.
protocol APIClient: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T
}

struct URLSessionAPIClient: APIClient {
    let baseURL: URL
    let session: URLSession
    let timeout: TimeInterval

    init(baseURL: URL = AppConfiguration.apiBaseURL,
         session: URLSession = .shared,
         timeout: TimeInterval = 15) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        guard let url = endpoint.url(relativeTo: baseURL) else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request)

        NetworkLogger.logResponse(
            endpoint: endpoint,
            url: url,
            response: response,
            data: data
        )

        switch response.statusCode {
        case 200..<300: break
        case 404: throw NetworkError.notFound
        default: throw NetworkError.server(statusCode: response.statusCode)
        }

        guard !data.isEmpty else { throw NetworkError.emptyResponse }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decoding
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
            return (data, http)
        } catch let error as URLError {
            throw NetworkError(urlError: error)
        }
    }
}
