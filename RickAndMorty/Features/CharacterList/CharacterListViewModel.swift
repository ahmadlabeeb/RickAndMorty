import Foundation
import Observation

enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case apiOrder, nameAscending, nameDescending

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apiOrder: "Default"
        case .nameAscending: "Name (A–Z)"
        case .nameDescending: "Name (Z–A)"
        }
    }
}

@MainActor
@Observable
final class CharacterListViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error(String)
    }

    // MARK: Observable UI state
    private(set) var state: State = .idle
    private(set) var displayedCharacters: [RMCharacter] = []
    private(set) var isPaginating = false
    private(set) var isRefreshing = false
    private(set) var isShowingCachedData = false
    private(set) var paginationError: String?
    private(set) var refreshError: String?

    var searchText = ""
    var statusFilter: CharacterStatus?
    var sortOption: SortOption = .apiOrder {
        didSet { updateDisplayed() }
    }

    // MARK: Internals
    @ObservationIgnored private let repository: any CharacterRepository
    @ObservationIgnored private let searchDebounce: Duration
    @ObservationIgnored private let prefetchThreshold = 5
    @ObservationIgnored private var characters: [RMCharacter] = []
    @ObservationIgnored private var loadedIDs = Set<Int>()
    @ObservationIgnored private var nextPage = 1
    @ObservationIgnored private var hasNextPage = true
    /// Incremented on every reload; stale responses compare against it and are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var appliedQuery = CharacterQuery()
    @ObservationIgnored private(set) var reloadTask: Task<Void, Never>?
    @ObservationIgnored private(set) var paginationTask: Task<Void, Never>?

    init(repository: any CharacterRepository, searchDebounce: Duration = .milliseconds(400)) {
        self.repository = repository
        self.searchDebounce = searchDebounce
    }

    private var query: CharacterQuery {
        CharacterQuery(name: searchText, status: statusFilter)
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard state == .idle else { return }
        await reload()
    }

    /// Entry point for `.refreshable`. Runs in its own Task so SwiftUI cancelling the
    /// refresh closure doesn't cancel the network request half way.
    func refresh() async {
        await Task { await self.reload(isRefresh: true) }.value
    }

    func reload(isRefresh: Bool = false) async {
        generation += 1
        let gen = generation
        let requestQuery = query
        appliedQuery = requestQuery

        paginationTask?.cancel()
        paginationTask = nil
        isPaginating = false
        paginationError = nil
        refreshError = nil

        let keepContent = isRefresh && !characters.isEmpty
        if keepContent {
            isRefreshing = true
        } else {
            state = .loading
        }

        do {
            let page = try await repository.characters(page: 1, query: requestQuery)
            guard gen == generation else { return }
            characters = []
            loadedIDs = []
            append(page.characters)
            nextPage = 2
            hasNextPage = page.hasNextPage
            isShowingCachedData = page.isFromCache
            state = characters.isEmpty ? .empty : .loaded
        } catch {
            guard gen == generation else { return }
            if !ErrorMapper.isCancellation(error) {
                let message = ErrorMapper.message(for: error)
                if keepContent {
                    refreshError = message
                } else {
                    characters = []
                    loadedIDs = []
                    updateDisplayed()
                    state = .error(message)
                }
            }
        }
        isRefreshing = false
    }

    /// Called from each row's `onAppear`.
    func loadMoreIfNeeded(current: RMCharacter) {
        guard displayedCharacters.suffix(prefetchThreshold).contains(where: { $0.id == current.id }) else { return }
        paginationTask = Task { await self.loadNextPage() }
    }

    func retryPagination() {
        paginationError = nil
        paginationTask = Task { await self.loadNextPage() }
    }

    func loadNextPage() async {
        guard state == .loaded, hasNextPage, !isPaginating, !isRefreshing else { return }
        let gen = generation
        let page = nextPage
        isPaginating = true
        paginationError = nil

        do {
            let result = try await repository.characters(page: page, query: appliedQuery)
            guard gen == generation else { return }
            append(result.characters)
            nextPage = page + 1
            hasNextPage = result.hasNextPage
            isShowingCachedData = isShowingCachedData || result.isFromCache
        } catch {
            guard gen == generation else { return }
            if !ErrorMapper.isCancellation(error) {
                paginationError = ErrorMapper.message(for: error)
            }
        }
        isPaginating = false
    }

    // MARK: Search & filter

    func searchTextChanged() {
        scheduleReload(after: searchDebounce)
    }

    func filterChanged() {
        scheduleReload(after: .zero)
    }

    private func scheduleReload(after delay: Duration) {
        reloadTask?.cancel()
        guard query != appliedQuery else { return }
        reloadTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self else { return }
            await self.reload()
        }
    }

    // MARK: Helpers

    private func append(_ newCharacters: [RMCharacter]) {
        for character in newCharacters {
            // Prevent duplicate records (e.g. pages shifting while the user scrolls).
            if loadedIDs.insert(character.id).inserted {
                characters.append(character)
            }
        }
        updateDisplayed()
    }

    private func updateDisplayed() {
        switch sortOption {
        case .apiOrder:
            displayedCharacters = characters
        case .nameAscending:
            displayedCharacters = characters.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            displayedCharacters = characters.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }
    }
}
