import Testing
@testable import RickAndMorty

@Suite @MainActor
struct CharacterDetailViewModelTests {
    @Test func loadsEpisodesLazily() async {
        let repo = MockEpisodeRepository()
        let vm = CharacterDetailViewModel(character: .stub(episodeIDs: [1, 2]), episodeRepository: repo)

        #expect(vm.episodesState == .idle)
        #expect(repo.calls.isEmpty) // nothing fetched until the screen asks

        await vm.loadEpisodes()

        #expect(vm.episodesState == .loaded([.stub(id: 1), .stub(id: 2)]))
        #expect(repo.calls == [[1, 2]])
    }

    @Test func characterWithoutEpisodesIsEmptyAndMakesNoRequest() async {
        let repo = MockEpisodeRepository()
        let vm = CharacterDetailViewModel(character: .stub(episodeIDs: []), episodeRepository: repo)
        await vm.loadEpisodes()
        #expect(vm.episodesState == .empty)
        #expect(repo.calls.isEmpty)
    }

    @Test func repeatedLoadsDoNotRefetch() async {
        let repo = MockEpisodeRepository()
        let vm = CharacterDetailViewModel(character: .stub(), episodeRepository: repo)
        await vm.loadEpisodes()
        await vm.loadEpisodes()
        #expect(repo.calls.count == 1)
    }

    @Test func failureThenRetrySucceeds() async {
        let repo = MockEpisodeRepository { _ in throw NetworkError.noConnection }
        let vm = CharacterDetailViewModel(character: .stub(), episodeRepository: repo)

        await vm.loadEpisodes()
        #expect(vm.episodesState == .error(NetworkError.noConnection.errorDescription ?? ""))

        repo.setHandler { ids in ids.map(Episode.stub(id:)) }
        await vm.loadEpisodes()
        if case .loaded(let episodes) = vm.episodesState {
            #expect(episodes.count == 2)
        } else {
            Issue.record("Expected loaded state")
        }
    }

    @Test func cancellationResetsToIdle() async {
        let repo = MockEpisodeRepository { _ in throw CancellationError() }
        let vm = CharacterDetailViewModel(character: .stub(), episodeRepository: repo)
        await vm.loadEpisodes()
        #expect(vm.episodesState == .idle)
    }

    @Test func exposesCharacterDetails() {
        let vm = CharacterDetailViewModel(character: .stub(name: "Morty Smith"), episodeRepository: MockEpisodeRepository())
        #expect(vm.character.name == "Morty Smith")
    }
}
