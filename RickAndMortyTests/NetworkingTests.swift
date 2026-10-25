import Testing
import UIKit
@testable import RickAndMorty

private struct Probe: Decodable, Sendable, Equatable {
    let userName: String
}

/// URLProtocolStub uses shared static state, so everything that uses it runs serially.
@Suite(.serialized)
struct NetworkingTests {
    private let baseURL = URL(string: "https://example.com/api")!
    private var client: URLSessionAPIClient {
        URLSessionAPIClient(baseURL: baseURL, session: URLProtocolStub.makeSession())
    }

    // MARK: APIClient

    @Test func decodesSnakeCaseJSON() async throws {
        URLProtocolStub.respond(status: 200, body: Data(#"{"user_name":"rick"}"#.utf8))
        let probe: Probe = try await client.send(Endpoint(path: "probe"))
        #expect(probe == Probe(userName: "rick"))
    }

    @Test func buildsURLWithPathAndQuery() async throws {
        let captured = Capture()
        URLProtocolStub.handler = { request in
            captured.set(request.url)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"user_name":"x"}"#.utf8))
        }
        let _: Probe = try await client.send(.characters(page: 2, query: CharacterQuery(name: "rick", status: .alive)))
        let url = try #require(captured.url)
        #expect(url.path == "/api/character")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "page", value: "2")))
        #expect(items.contains(URLQueryItem(name: "name", value: "rick")))
        #expect(items.contains(URLQueryItem(name: "status", value: "alive")))
    }

    @Test func mapsNotFound() async {
        URLProtocolStub.respond(status: 404, body: Data(#"{"error":"There is nothing here"}"#.utf8))
        await #expect(throws: NetworkError.notFound) { let _: Probe = try await client.send(Endpoint(path: "x")) }
    }

    @Test func mapsServerError() async {
        URLProtocolStub.respond(status: 500, body: Data("oops".utf8))
        await #expect(throws: NetworkError.server(statusCode: 500)) { let _: Probe = try await client.send(Endpoint(path: "x")) }
    }

    @Test func mapsEmptyBody() async {
        URLProtocolStub.respond(status: 200, body: Data())
        await #expect(throws: NetworkError.emptyResponse) { let _: Probe = try await client.send(Endpoint(path: "x")) }
    }

    @Test func mapsMalformedJSONToDecodingError() async {
        URLProtocolStub.respond(status: 200, body: Data("not json".utf8))
        await #expect(throws: NetworkError.decoding) { let _: Probe = try await client.send(Endpoint(path: "x")) }
    }

    @Test func mapsOffline() async {
        URLProtocolStub.handler = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: NetworkError.noConnection) { let _: Probe = try await client.send(Endpoint(path: "x")) }
    }

    @Test func mapsTimeout() async {
        URLProtocolStub.handler = { _ in throw URLError(.timedOut) }
        await #expect(throws: NetworkError.timeout) { let _: Probe = try await client.send(Endpoint(path: "x")) }
    }

    // MARK: NetworkLogger

    @Test func networkLoggerFormatsPrettyJSON() {
        let json = #"{"name":"Rick","status":"Alive"}"#
        let data = Data(json.utf8)
        let url = URL(string: "https://rickandmortyapi.com/api/character/1")!
        let params: [String: Any] = ["page": 1]

        let message = NetworkLogger.formatMessage(
            url: url,
            parameters: params,
            statusCode: 200,
            data: data
        )

        #expect(message.contains("URL: https://rickandmortyapi.com/api/character/1"))
        #expect(message.contains("\"page\": 1") || message.contains("\"page\":1"))
        #expect(message.contains("Response Code: 200"))
        #expect(message.contains("\"name\" : \"Rick\"") || message.contains("\"name\": \"Rick\""))
        #expect(message.contains("\"status\" : \"Alive\"") || message.contains("\"status\": \"Alive\""))
    }

    @Test func networkLoggerHandlesNonJSONOrEmptyData() {
        let emptyMessage = NetworkLogger.formatMessage(
            url: nil,
            parameters: nil,
            statusCode: 500,
            data: Data()
        )
        #expect(emptyMessage.contains("URL: N/A"))
        #expect(emptyMessage.contains("Parameters: None"))
        #expect(emptyMessage.contains("Response Code: 500"))
        #expect(emptyMessage.contains("(Empty)"))

        let textMessage = NetworkLogger.formatMessage(
            url: URL(string: "https://example.com")!,
            parameters: [:],
            statusCode: 502,
            data: Data("Gateway Error".utf8)
        )
        #expect(textMessage.contains("Parameters: None"))
        #expect(textMessage.contains("Gateway Error"))
    }

    // MARK: ImageLoader

    @Test func imageLoaderCachesInMemory() async throws {
        let hits = Counter()
        let png = Self.makePNG()
        URLProtocolStub.handler = { request in
            hits.increment()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, png)
        }
        let loader = ImageLoader(session: URLProtocolStub.makeSession())
        let url = URL(string: "https://example.com/a.png")!

        _ = try await loader.image(for: url)
        _ = try await loader.image(for: url)

        #expect(hits.value == 1)
        #expect(loader.cachedImage(for: url) != nil)
    }

    @Test func imageLoaderSharesConcurrentRequests() async throws {
        let hits = Counter()
        let png = Self.makePNG()
        URLProtocolStub.handler = { request in
            hits.increment()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, png)
        }
        let loader = ImageLoader(session: URLProtocolStub.makeSession())
        let url = URL(string: "https://example.com/b.png")!

        async let first = loader.image(for: url)
        async let second = loader.image(for: url)
        _ = try await (first, second)

        #expect(hits.value == 1)
    }

    @Test func imageLoaderRejectsInvalidData() async {
        URLProtocolStub.respond(status: 200, body: Data("not an image".utf8))
        let loader = ImageLoader(session: URLProtocolStub.makeSession())
        await #expect(throws: NetworkError.invalidResponse) {
            _ = try await loader.image(for: URL(string: "https://example.com/c.png")!)
        }
    }

    private static func makePNG() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

private final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URL?
    var url: URL? { lock.withLock { stored } }
    func set(_ url: URL?) { lock.withLock { stored = url } }
}
