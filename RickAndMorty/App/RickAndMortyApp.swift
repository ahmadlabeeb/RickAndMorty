import SwiftUI

@main
struct RickAndMortyApp: App {
    private let container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}

struct RootView: View {
    private let container: AppContainer
    @State private var listViewModel: CharacterListViewModel

    init(container: AppContainer) {
        self.container = container
        _listViewModel = State(initialValue: container.makeCharacterListViewModel())
    }

    var body: some View {
        NavigationStack {
            CharacterListView(viewModel: listViewModel)
                .navigationDestination(for: RMCharacter.self) { character in
                    CharacterDetailView(viewModel: container.makeCharacterDetailViewModel(for: character))
                }
        }
        .environment(\.imageLoader, container.imageLoader)
    }
}
