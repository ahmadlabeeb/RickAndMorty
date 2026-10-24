import Foundation
import SwiftData
import Testing
@testable import RickAndMorty

@Suite struct CharacterRepositoryTests {
    private let client = MockAPIClient()
    private let cache = MockCharacterCache()
    private var sut: DefaultCharacterRepository { DefaultCharacterRepository(client: client, cache: cache) }

    @Test func mapsDTOsToDomainModels() async throws {
        client.stub { _ in try Fixtures.decodeCharacterPage(next: "https://x/page=2") }

        let page = try await sut.characters(page: 1, query: CharacterQuery())

        #expect(page.characters.count == 2)
        #expect(page.hasNextPage)
        #expect(!page.isFromCache)
        let rick = try #require(page.characters.first)
        #expect(rick.name == "Rick Sanchez")
        #expect(rick.status == .alive)
        #expect(rick.originName == "Earth (C-137)")
        #expect(rick.episodeIDs == [1, 2])
        #expect(page.characters[1].status == .unknown)
    }

    @Test func lastPageHasNoNextPage() async throws {
        client.stub { _ in try Fixtures.decodeCharacterPage(next: nil) }
        let page = try await sut.characters(page: 2, query: CharacterQuery())
        #expect(!page.hasNextPage)
    }

    @Test func requestsExpectedEndpoint() async throws {
        client.stub { _ in try Fixtures.decodeCharacterPage() }
        let query = CharacterQuery(name: "rick", status: .alive)
        _ = try await sut.characters(page: 3, query: query)
        #expect(client.requestedEndpoints == [.characters(page: 3, query: query)])
    }

    @Test func cachesUnfilteredPages() async throws {
        client.stub { _ in try Fixtures.decodeCharacterPage() }
        _ = try await sut.characters(page: 1, query: CharacterQuery())
        #expect(await cache.pages[1]?.count == 2)
    }

    @Test func doesNotCacheFilteredResults() async throws {
        client.stub { _ in try Fixtures.decodeCharacterPage() }
        _ = try await sut.characters(page: 1, query: CharacterQuery(name: "rick"))
        #expect(await cache.pages.isEmpty)
    }

    @Test func notFoundBecomesEmptyPage() async throws {
        client.stub { _ in throw NetworkError.notFound }
        let page = try await sut.characters(page: 1, query: CharacterQuery(name: "zzzz"))
        #expect(page.characters.isEmpty)
        #expect(!page.hasNextPage)
    }

    @Test func fallsBackToCacheWhenOffline() async throws {
        await cache.save([.stub(id: 1)], page: 1)
        await cache.save([.stub(id: 2)], page: 2)
        client.stub { _ in throw NetworkError.noConnection }

        let page = try await sut.characters(page: 1, query: CharacterQuery())

        #expect(page.isFromCache)
        #expect(page.characters.map(\.id) == [1])
        #expect(page.hasNextPage)
    }

    @Test func offlineWithEmptyCacheThrows() async {
        client.stub { _ in throw NetworkError.noConnection }
        await #expect(throws: NetworkError.noConnection) {
            try await sut.characters(page: 1, query: CharacterQuery())
        }
    }

    @Test func offlineFilteredSearchDoesNotUseCache() async {
        await cache.save([.stub(id: 1)], page: 1)
        client.stub { _ in throw NetworkError.timeout }
        await #expect(throws: NetworkError.timeout) {
            try await sut.characters(page: 1, query: CharacterQuery(name: "rick"))
        }
    }

    @Test func serverErrorsDoNotFallBackToCache() async {
        await cache.save([.stub(id: 1)], page: 1)
        client.stub { _ in throw NetworkError.server(statusCode: 500) }
        await #expect(throws: NetworkError.server(statusCode: 500)) {
            try await sut.characters(page: 1, query: CharacterQuery())
        }
    }
}

@Suite struct EpisodeRepositoryTests {
    private let client = MockAPIClient()
    private var sut: DefaultEpisodeRepository { DefaultEpisodeRepository(client: client) }

    @Test func batchesIdsIntoSingleRequest() async throws {
        client.stub { endpoint in
            try Fixtures.decodeEpisodes(ids: [1, 2, 3])
        }
        let repo = sut
        let episodes = try await repo.episodes(ids: [3, 1, 2, 2])

        #expect(client.requestedEndpoints == [.episodes(ids: [1, 2, 3])])
        #expect(episodes.map(\.id) == [1, 2, 3])
        #expect(episodes.first?.code == "S01E01")
    }

    @Test func handlesSingleObjectResponse() async throws {
        client.stub { _ in try Fixtures.decodeEpisodes(ids: [7]) }
        let episodes = try await sut.episodes(ids: [7])
        #expect(episodes.map(\.id) == [7])
    }

    @Test func secondCallUsesCacheAndSkipsNetwork() async throws {
        client.stub { _ in try Fixtures.decodeEpisodes(ids: [1, 2]) }
        let repo = sut
        _ = try await repo.episodes(ids: [1, 2])
        _ = try await repo.episodes(ids: [1, 2])
        #expect(client.requestedEndpoints.count == 1)
    }

    @Test func onlyFetchesMissingEpisodes() async throws {
        let repo = sut
        client.stub { _ in try Fixtures.decodeEpisodes(ids: [1, 2]) }
        _ = try await repo.episodes(ids: [1, 2])
        client.stub { _ in try Fixtures.decodeEpisodes(ids: [3]) }
        let result = try await repo.episodes(ids: [1, 2, 3])

        #expect(client.requestedEndpoints.last == .episodes(ids: [3]))
        #expect(result.map(\.id) == [1, 2, 3])
    }

    @Test func emptyIdsMakeNoRequest() async throws {
        let episodes = try await sut.episodes(ids: [])
        #expect(episodes.isEmpty)
        #expect(client.requestedEndpoints.isEmpty)
    }

    @Test func propagatesErrors() async {
        client.stub { _ in throw NetworkError.noConnection }
        await #expect(throws: NetworkError.noConnection) { try await sut.episodes(ids: [1]) }
    }
}

@Suite struct SwiftDataCharacterCacheTests {
    private func makeCache() throws -> SwiftDataCharacterCache {
        let container = try ModelContainer(
            for: CachedCharacter.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataCharacterCache(modelContainer: container)
    }

    @Test func roundTripsCharactersByPage() async throws {
        let cache = try makeCache()
        await cache.save([.stub(id: 2), .stub(id: 1)], page: 1)
        await cache.save([.stub(id: 3)], page: 2)

        let page1 = await cache.characters(page: 1)
        #expect(page1.map(\.id) == [1, 2])
        #expect(page1.first == .stub(id: 1))
        #expect(await cache.characters(page: 2).map(\.id) == [3])
        #expect(await cache.characters(page: 9).isEmpty)
    }

    @Test func savingSameCharacterUpdatesInsteadOfDuplicating() async throws {
        let cache = try makeCache()
        await cache.save([.stub(id: 1, name: "Old")], page: 1)
        await cache.save([.stub(id: 1, name: "New")], page: 1)

        let result = await cache.characters(page: 1)
        #expect(result.count == 1)
        #expect(result.first?.name == "New")
    }
}
