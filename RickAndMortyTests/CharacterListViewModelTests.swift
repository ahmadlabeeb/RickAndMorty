import Testing
@testable import RickAndMorty

@Suite @MainActor
struct CharacterListViewModelTests {
    private func makeSUT(_ handler: @escaping MockCharacterRepository.Handler = { page, _ in
        .stub(ids: ((page - 1) * 3 + 1)...(page * 3), hasNext: page < 3)
    }) -> (CharacterListViewModel, MockCharacterRepository) {
        let repo = MockCharacterRepository(handler: handler)
        return (CharacterListViewModel(repository: repo, searchDebounce: .zero), repo)
    }

    @Test func startsIdle() {
        let (vm, _) = makeSUT()
        #expect(vm.state == .idle)
    }

    @Test func initialLoadSucceeds() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        #expect(vm.state == .loaded)
        #expect(vm.displayedCharacters.map(\.id) == [1, 2, 3])
        #expect(repo.calls == [.init(page: 1, query: CharacterQuery())])
    }

    @Test func loadIfNeededOnlyLoadsOnce() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        await vm.loadIfNeeded()
        #expect(repo.calls.count == 1)
    }

    @Test func emptyResultShowsEmptyState() async {
        let (vm, _) = makeSUT { _, _ in .empty }
        await vm.loadIfNeeded()
        #expect(vm.state == .empty)
    }

    @Test func failureShowsErrorThenRetrySucceeds() async {
        let (vm, repo) = makeSUT { _, _ in throw NetworkError.noConnection }
        await vm.loadIfNeeded()
        guard case .error(let message) = vm.state else { Issue.record("Expected error state"); return }
        #expect(message == NetworkError.noConnection.errorDescription)

        repo.setHandler { _, _ in .stub() }
        await vm.reload()
        #expect(vm.state == .loaded)
    }

    @Test func paginationAppendsNextPage() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        await vm.loadNextPage()
        #expect(vm.displayedCharacters.map(\.id) == [1, 2, 3, 4, 5, 6])
        #expect(repo.calls.map(\.page) == [1, 2])
    }

    @Test func paginationStopsAfterLastPage() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        await vm.loadNextPage()
        await vm.loadNextPage()
        await vm.loadNextPage() // page 3 was the last
        #expect(repo.calls.map(\.page) == [1, 2, 3])
        #expect(vm.displayedCharacters.count == 9)
    }

    @Test func duplicatesAreNotAppended() async {
        let (vm, _) = makeSUT { page, _ in
            page == 1 ? .stub(ids: 1...3, hasNext: true) : .stub(ids: 3...5, hasNext: false)
        }
        await vm.loadIfNeeded()
        await vm.loadNextPage()
        #expect(vm.displayedCharacters.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test func concurrentPaginationRequestsAreCoalesced() async {
        let (vm, repo) = makeSUT { page, _ in
            try await Task.sleep(for: .milliseconds(50))
            return .stub(ids: ((page - 1) * 3 + 1)...(page * 3), hasNext: true)
        }
        await vm.loadIfNeeded()
        async let a: Void = vm.loadNextPage()
        async let b: Void = vm.loadNextPage()
        _ = await (a, b)
        #expect(repo.calls.filter { $0.page == 2 }.count == 1)
    }

    @Test func paginationFailureKeepsListAndAllowsRetry() async {
        let (vm, repo) = makeSUT { page, _ in
            if page == 1 { return .stub(ids: 1...3, hasNext: true) }
            throw NetworkError.timeout
        }
        await vm.loadIfNeeded()
        await vm.loadNextPage()

        #expect(vm.state == .loaded)
        #expect(vm.displayedCharacters.count == 3)
        #expect(vm.paginationError == NetworkError.timeout.errorDescription)
        #expect(!vm.isPaginating)

        repo.setHandler { _, _ in .stub(ids: 4...6) }
        vm.retryPagination()
        await vm.paginationTask?.value
        #expect(vm.displayedCharacters.count == 6)
        #expect(vm.paginationError == nil)
    }

    @Test func rowNearEndTriggersNextPage() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        vm.loadMoreIfNeeded(current: vm.displayedCharacters[0]) // threshold is last 5 of 3 → all rows
        await vm.paginationTask?.value
        #expect(repo.calls.map(\.page) == [1, 2])
    }

    @Test func refreshReplacesContent() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        await vm.loadNextPage()
        #expect(vm.displayedCharacters.count == 6)

        repo.setHandler { _, _ in .stub(ids: 10...11) }
        await vm.refresh()
        #expect(vm.displayedCharacters.map(\.id) == [10, 11])
        #expect(!vm.isRefreshing)
    }

    @Test func refreshFailureKeepsExistingContent() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        repo.setHandler { _, _ in throw NetworkError.noConnection }
        await vm.refresh()
        #expect(vm.state == .loaded)
        #expect(vm.displayedCharacters.count == 3)
        #expect(vm.refreshError == NetworkError.noConnection.errorDescription)
    }

    @Test func cachedPageSetsOfflineFlag() async {
        let (vm, _) = makeSUT { _, _ in .stub(fromCache: true) }
        await vm.loadIfNeeded()
        #expect(vm.isShowingCachedData)
    }

    @Test func searchReloadsWithQuery() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        vm.searchText = "  rick "
        vm.searchTextChanged()
        await vm.reloadTask?.value
        #expect(repo.calls.last == .init(page: 1, query: CharacterQuery(name: "  rick ", status: nil)))
        #expect(repo.calls.last?.query.trimmedName == "rick")
    }

    @Test func rapidSearchChangesAreDebounced() async {
        let repo = MockCharacterRepository()
        let vm = CharacterListViewModel(repository: repo, searchDebounce: .milliseconds(50))
        await vm.loadIfNeeded()
        for text in ["r", "ri", "ric", "rick"] {
            vm.searchText = text
            vm.searchTextChanged()
        }
        await vm.reloadTask?.value
        #expect(repo.calls.count == 2) // initial load + one debounced search
        #expect(repo.calls.last?.query.name == "rick")
    }

    @Test func statusFilterReloadsWithStatus() async {
        let (vm, repo) = makeSUT()
        await vm.loadIfNeeded()
        vm.statusFilter = .dead
        vm.filterChanged()
        await vm.reloadTask?.value
        #expect(repo.calls.last?.query.status == .dead)
    }

    @Test func sortingIsAppliedLocally() async {
        let (vm, repo) = makeSUT { _, _ in
            CharactersPage(characters: [.stub(id: 1, name: "Morty"), .stub(id: 2, name: "Rick"), .stub(id: 3, name: "Birdperson")],
                           hasNextPage: false, isFromCache: false)
        }
        await vm.loadIfNeeded()

        vm.sortOption = .nameAscending
        #expect(vm.displayedCharacters.map(\.name) == ["Birdperson", "Morty", "Rick"])
        vm.sortOption = .nameDescending
        #expect(vm.displayedCharacters.map(\.name) == ["Rick", "Morty", "Birdperson"])
        #expect(repo.calls.count == 1) // no extra network calls
    }

    @Test func staleResponseIsIgnored() async {
        let (vm, repo) = makeSUT { _, query in
            if query.name == "slow" {
                try await Task.sleep(for: .milliseconds(150))
                return .stub(ids: 100...101)
            }
            return .stub(ids: 1...2)
        }
        vm.searchText = "slow"
        let slow = Task { await vm.reload() }
        try? await Task.sleep(for: .milliseconds(20))
        vm.searchText = "fast"
        await vm.reload()
        await slow.value

        #expect(vm.displayedCharacters.map(\.id) == [1, 2])
        #expect(repo.calls.count == 2)
    }
}
