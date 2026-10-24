import Foundation
import SwiftData

/// Persisted character, stored as JSON so schema changes to the domain model stay cheap.
@Model
final class CachedCharacter {
    @Attribute(.unique) var id: Int
    var page: Int
    var payload: Data

    init(id: Int, page: Int, payload: Data) {
        self.id = id
        self.page = page
        self.payload = payload
    }
}

protocol CharacterCache: Sendable {
    func save(_ characters: [RMCharacter], page: Int) async
    func characters(page: Int) async -> [RMCharacter]
}

/// SwiftData-backed cache. `@ModelActor` gives it its own serial executor and ModelContext,
/// so database work never touches the main thread.
@ModelActor
actor SwiftDataCharacterCache: CharacterCache {
    func save(_ characters: [RMCharacter], page: Int) {
        let encoder = JSONEncoder()
        for character in characters {
            guard let payload = try? encoder.encode(character) else { continue }
            let id = character.id
            let descriptor = FetchDescriptor<CachedCharacter>(predicate: #Predicate { $0.id == id })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.page = page
                existing.payload = payload
            } else {
                modelContext.insert(CachedCharacter(id: id, page: page, payload: payload))
            }
        }
        try? modelContext.save()
    }

    func characters(page: Int) -> [RMCharacter] {
        let descriptor = FetchDescriptor<CachedCharacter>(
            predicate: #Predicate { $0.page == page },
            sortBy: [SortDescriptor(\.id)]
        )
        let decoder = JSONDecoder()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.compactMap { try? decoder.decode(RMCharacter.self, from: $0.payload) }
    }
}

/// Used if the persistent store cannot be created, so the app still works online.
struct NoOpCharacterCache: CharacterCache {
    func save(_ characters: [RMCharacter], page: Int) async {}
    func characters(page: Int) async -> [RMCharacter] { [] }
}
