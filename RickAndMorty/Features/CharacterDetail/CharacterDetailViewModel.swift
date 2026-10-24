import Foundation
import Observation

@MainActor
@Observable
final class CharacterDetailViewModel {
    enum EpisodesState: Equatable {
        case idle
        case loading
        case loaded([Episode])
        case empty
        case error(String)
    }

    let character: RMCharacter
    private(set) var episodesState: EpisodesState = .idle

    @ObservationIgnored private let episodeRepository: any EpisodeRepository

    init(character: RMCharacter, episodeRepository: any EpisodeRepository) {
        self.character = character
        self.episodeRepository = episodeRepository
    }

    /// Lazy: only called when the details screen appears. Safe to call repeatedly.
    func loadEpisodes() async {
        switch episodesState {
        case .loading, .loaded, .empty: return
        case .idle, .error: break
        }

        guard !character.episodeIDs.isEmpty else {
            episodesState = .empty
            return
        }

        episodesState = .loading
        do {
            let episodes = try await episodeRepository.episodes(ids: character.episodeIDs)
            episodesState = episodes.isEmpty ? .empty : .loaded(episodes)
        } catch {
            // View disappeared mid-flight: go back to idle so we retry on next appearance.
            episodesState = ErrorMapper.isCancellation(error) ? .idle : .error(ErrorMapper.message(for: error))
        }
    }
}
