import SwiftUI

struct CharacterDetailView: View {
    @State private var viewModel: CharacterDetailViewModel

    init(viewModel: CharacterDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var character: RMCharacter { viewModel.character }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                info
                episodes
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadEpisodes() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            CachedAsyncImage(url: character.imageURL)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 360)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("Photo of \(character.name)")

            Text(character.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    private var info: some View {
        VStack(spacing: 0) {
            InfoRow(title: "Status", value: character.status.displayName)
            Divider()
            InfoRow(title: "Species", value: character.species)
            Divider()
            InfoRow(title: "Gender", value: character.gender)
            Divider()
            InfoRow(title: "Origin", value: character.originName)
            Divider()
            InfoRow(title: "Location", value: character.locationName)
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Episodes")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            switch viewModel.episodesState {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading episodes…").foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            case .empty:
                Text("No episodes available.").foregroundStyle(.secondary)
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).foregroundStyle(.secondary)
                    Button("Retry") { Task { await viewModel.loadEpisodes() } }
                        .buttonStyle(.bordered)
                }
            case .loaded(let episodes):
                LazyVStack(spacing: 8) {
                    ForEach(episodes) { EpisodeRow(episode: $0) }
                }
            }
        }
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value.isEmpty ? "—" : value).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct EpisodeRow: View {
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            Text(episode.code)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.tint.opacity(0.15), in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.name).font(.subheadline.weight(.medium))
                Text(episode.airDate).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
