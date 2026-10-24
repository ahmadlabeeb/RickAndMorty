import Foundation
@testable import RickAndMorty

// MARK: - Builders

extension RMCharacter {
    static func stub(id: Int = 1,
                     name: String = "Rick Sanchez",
                     status: CharacterStatus = .alive,
                     episodeIDs: [Int] = [1, 2]) -> RMCharacter {
        RMCharacter(id: id, name: name, status: status, species: "Human", gender: "Male",
                    originName: "Earth (C-137)", locationName: "Citadel of Ricks",
                    imageURL: URL(string: "https://example.com/\(id).jpeg"), episodeIDs: episodeIDs)
    }
}

extension CharactersPage {
    static func stub(ids: ClosedRange<Int> = 1...3, hasNext: Bool = false, fromCache: Bool = false) -> CharactersPage {
        CharactersPage(characters: ids.map { RMCharacter.stub(id: $0, name: "Character \($0)") },
                       hasNextPage: hasNext, isFromCache: fromCache)
    }
}

extension Episode {
    static func stub(id: Int) -> Episode {
        Episode(id: id, name: "Episode \(id)", airDate: "December 2, 2013", code: String(format: "S01E%02d", id))
    }
}

// MARK: - Fixtures

enum Fixtures {
    static func characterPageJSON(next: String?) -> String {
        let nextValue = next.map { "\"\($0)\"" } ?? "null"
        return """
        {"info":{"count":2,"pages":2,"next":\(nextValue),"prev":null},
         "results":[
          {"id":1,"name":"Rick Sanchez","status":"Alive","species":"Human","type":"","gender":"Male",
           "origin":{"name":"Earth (C-137)","url":""},"location":{"name":"Citadel of Ricks","url":""},
           "image":"https://rickandmortyapi.com/api/character/avatar/1.jpeg",
           "episode":["https://rickandmortyapi.com/api/episode/1","https://rickandmortyapi.com/api/episode/2"],
           "url":"","created":""},
          {"id":2,"name":"Morty Smith","status":"unknown","species":"Human","type":"","gender":"Male",
           "origin":{"name":"unknown","url":""},"location":{"name":"Earth","url":""},
           "image":"https://rickandmortyapi.com/api/character/avatar/2.jpeg",
           "episode":["https://rickandmortyapi.com/api/episode/1"],"url":"","created":""}
         ]}
        """
    }

    static func decodeCharacterPage(next: String? = nil) throws -> CharacterPageDTO {
        try decode(characterPageJSON(next: next))
    }

    static func decodeEpisodes(ids: [Int]) throws -> EpisodeListDTO {
        let items = ids.map {
            "{\"id\":\($0),\"name\":\"Episode \($0)\",\"air_date\":\"December 2, 2013\",\"episode\":\"S01E0\($0)\"}"
        }
        // Mirrors the real API: a single id returns an object, several return an array.
        let json = ids.count == 1 ? items[0] : "[" + items.joined(separator: ",") + "]"
        return try decode(json)
    }

    private static func decode<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}

// MARK: - Mocks

final class MockAPIClient: APIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Endpoint) throws -> Any)?
    private var endpoints: [Endpoint] = []

    var requestedEndpoints: [Endpoint] { lock.withLock { endpoints } }

    func stub(_ handler: @escaping @Sendable (Endpoint) throws -> Any) {
        lock.withLock { self.handler = handler }
    }

    func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        let handler = lock.withLock { () -> (@Sendable (Endpoint) throws -> Any)? in
            endpoints.append(endpoint)
            return self.handler
        }
        guard let value = try handler?(endpoint) as? T else { throw NetworkError.invalidResponse }
        return value
    }
}

actor MockCharacterCache: CharacterCache {
    private(set) var pages: [Int: [RMCharacter]] = [:]

    func save(_ characters: [RMCharacter], page: Int) { pages[page] = characters }
    func characters(page: Int) -> [RMCharacter] { pages[page] ?? [] }
}

final class MockCharacterRepository: CharacterRepository, @unchecked Sendable {
    typealias Handler = @Sendable (Int, CharacterQuery) async throws -> CharactersPage
    struct Call: Equatable { let page: Int; let query: CharacterQuery }

    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [Call] = []

    init(handler: @escaping Handler = { _, _ in .stub() }) { self.handler = handler }

    var calls: [Call] { lock.withLock { recorded } }

    func setHandler(_ handler: @escaping Handler) { lock.withLock { self.handler = handler } }

    func characters(page: Int, query: CharacterQuery) async throws -> CharactersPage {
        let handler = lock.withLock { () -> Handler in
            recorded.append(Call(page: page, query: query))
            return self.handler
        }
        return try await handler(page, query)
    }
}

final class MockEpisodeRepository: EpisodeRepository, @unchecked Sendable {
    typealias Handler = @Sendable ([Int]) async throws -> [Episode]
    private let lock = NSLock()
    private var handler: Handler
    private var recorded: [[Int]] = []

    init(handler: @escaping Handler = { ids in ids.map(Episode.stub(id:)) }) { self.handler = handler }

    var calls: [[Int]] { lock.withLock { recorded } }
    func setHandler(_ handler: @escaping Handler) { lock.withLock { self.handler = handler } }

    func episodes(ids: [Int]) async throws -> [Episode] {
        let handler = lock.withLock { () -> Handler in
            recorded.append(ids)
            return self.handler
        }
        return try await handler(ids)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

// MARK: - URLProtocol stub

final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: config)
    }

    static func respond(status: Int, body: Data = Data()) {
        handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }
    }
}
