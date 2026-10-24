import Foundation
import SwiftData

/// Composition root. Everything is built here and handed down via constructor injection;
/// view models only ever see protocols, which is what makes them unit-testable.
@MainActor
final class AppContainer {
    let characterRepository: any CharacterRepository
    let episodeRepository: any EpisodeRepository
    let imageLoader: any ImageLoading

    init(characterRepository: any CharacterRepository,
         episodeRepository: any EpisodeRepository,
         imageLoader: any ImageLoading) {
        self.characterRepository = characterRepository
        self.episodeRepository = episodeRepository
        self.imageLoader = imageLoader
    }

    static func live() -> AppContainer {
        let client = URLSessionAPIClient()
        return AppContainer(
            characterRepository: DefaultCharacterRepository(client: client, cache: makePersistentCache()),
            episodeRepository: DefaultEpisodeRepository(client: client),
            imageLoader: ImageLoader.shared
        )
    }

    private static func makePersistentCache() -> any CharacterCache {
        if let container = try? ModelContainer(for: CachedCharacter.self) {
            return SwiftDataCharacterCache(modelContainer: container)
        }
        return NoOpCharacterCache()
    }

    // MARK: View model factories

    func makeCharacterListViewModel() -> CharacterListViewModel {
        CharacterListViewModel(repository: characterRepository)
    }

    func makeCharacterDetailViewModel(for character: RMCharacter) -> CharacterDetailViewModel {
        CharacterDetailViewModel(character: character, episodeRepository: episodeRepository)
    }
}
