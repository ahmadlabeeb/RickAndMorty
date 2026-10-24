import SwiftUI

struct CharacterListView: View {
    @Bindable var viewModel: CharacterListViewModel

    var body: some View {
        content
            .navigationTitle("Characters")
            .searchable(text: $viewModel.searchText, prompt: "Search characters")
            .onChange(of: viewModel.searchText) { viewModel.searchTextChanged() }
            .onChange(of: viewModel.statusFilter) { viewModel.filterChanged() }
            .toolbar { toolbar }
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading characters…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ContentUnavailableView {
                Label("Something went wrong", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await viewModel.reload() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retryButton")
            }
        case .empty:
            ContentUnavailableView {
                Label("No characters found", systemImage: "person.slash")
            } description: {
                Text("Try a different search or filter.")
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            if viewModel.isShowingCachedData || viewModel.refreshError != nil {
                Section { banner }
            }
            ForEach(viewModel.displayedCharacters) { character in
                NavigationLink(value: character) {
                    CharacterRow(character: character)
                }
                .onAppear { viewModel.loadMoreIfNeeded(current: character) }
            }
            footer
        }
        .listStyle(.plain)
        .refreshable { await viewModel.refresh() }
        .accessibilityIdentifier("characterList")
    }

    private var banner: some View {
        Label(
            viewModel.refreshError.map { "Couldn't refresh: \($0)" } ?? "Offline – showing saved characters.",
            systemImage: "wifi.slash"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.isPaginating {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
            .accessibilityLabel("Loading more characters")
        } else if let message = viewModel.paginationError {
            VStack(spacing: 8) {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Retry") { viewModel.retryPagination() }
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Status", selection: $viewModel.statusFilter) {
                    Text("All").tag(CharacterStatus?.none)
                    ForEach(CharacterStatus.allCases) { status in
                        Text(status.displayName).tag(CharacterStatus?.some(status))
                    }
                }
                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter and sort")
        }
    }
}

struct CharacterRow: View {
    let character: RMCharacter
    @ScaledMetric(relativeTo: .body) private var imageSize: CGFloat = 64

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: character.imageURL)
                .frame(width: imageSize, height: imageSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name).font(.headline)
                Text(character.species).font(.subheadline).foregroundStyle(.secondary)
                StatusBadge(status: character.status)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens character details")
    }
}

struct StatusBadge: View {
    let status: CharacterStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(status.displayName)
        }
        .font(.caption.weight(.medium))
    }

    private var color: Color {
        switch status {
        case .alive: .green
        case .dead: .red
        case .unknown: .gray
        }
    }
}
