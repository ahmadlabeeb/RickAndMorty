import Foundation

enum CharacterStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case alive = "Alive"
    case dead = "Dead"
    case unknown = "unknown"

    var id: String { rawValue }
    var displayName: String { self == .unknown ? "Unknown" : rawValue }
    /// Value used by the API's `status` query parameter.
    var apiValue: String { rawValue.lowercased() }

    init(apiValue: String) {
        self = Self.allCases.first { $0.apiValue == apiValue.lowercased() } ?? .unknown
    }
}

/// Named `RMCharacter` to avoid shadowing Swift's `Character`.
struct RMCharacter: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let status: CharacterStatus
    let species: String
    let gender: String
    let originName: String
    let locationName: String
    let imageURL: URL?
    let episodeIDs: [Int]
}

struct Episode: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let airDate: String
    /// e.g. "S01E01"
    let code: String
}

struct CharacterQuery: Equatable, Sendable {
    var name: String = ""
    var status: CharacterStatus?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// True when no search/filter is applied (only then do we cache for offline use).
    var isEmpty: Bool { trimmedName.isEmpty && status == nil }
}

struct CharactersPage: Sendable {
    let characters: [RMCharacter]
    let hasNextPage: Bool
    let isFromCache: Bool

    static let empty = CharactersPage(characters: [], hasNextPage: false, isFromCache: false)
}
