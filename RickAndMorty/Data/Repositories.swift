import Foundation

protocol CharacterRepository: Sendable {
    func characters(page: Int, query: CharacterQuery) async throws -> CharactersPage
}

protocol EpisodeRepository: Sendable {
    func episodes(ids: [Int]) async throws -> [Episode]
}

struct DefaultCharacterRepository: CharacterRepository {
    private let client: any APIClient
    private let cache: any CharacterCache

    init(client: any APIClient, cache: any CharacterCache) {
        self.client = client
        self.cache = cache
    }

    func characters(page: Int, query: CharacterQuery) async throws -> CharactersPage {
        do {
            let dto: CharacterPageDTO = try await client.send(.characters(page: page, query: query))
            let characters = dto.results.map(RMCharacter.init(dto:))
            if query.isEmpty {
                await cache.save(characters, page: page)
            }
            return CharactersPage(characters: characters, hasNextPage: dto.info.next != nil, isFromCache: false)
        } catch NetworkError.notFound {
            // The API answers 404 when a search/filter has no matches.
            return .empty
        } catch let error as NetworkError where error.isConnectivityIssue && query.isEmpty {
            let cached = await cache.characters(page: page)
            guard !cached.isEmpty else { throw error }
            let hasNext = !(await cache.characters(page: page + 1)).isEmpty
            return CharactersPage(characters: cached, hasNextPage: hasNext, isFromCache: true)
        }
    }
}

/// An actor so the in-memory episode cache is race-free under Swift 6.
actor DefaultEpisodeRepository: EpisodeRepository {
    private let client: any APIClient
    private var cache: [Int: Episode] = [:]

    init(client: any APIClient) {
        self.client = client
    }

    func episodes(ids: [Int]) async throws -> [Episode] {
        let unique = Array(Set(ids)).sorted()
        guard !unique.isEmpty else { return [] }

        // Only request what we don't already have, in ONE batched call.
        let missing = unique.filter { cache[$0] == nil }
        if !missing.isEmpty {
//            let dto: EpisodeListDTO = try await client.send(.episodes(ids: missing))
//            for episode in dto.episodes {
//                cache[episode.id] = Episode(dto: episode)
//            }
        }
        return unique.compactMap { cache[$0] }
    }
}
