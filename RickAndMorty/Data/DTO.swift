import Foundation

struct Info: Decodable, Sendable { let next: String? }

struct CharacterPageDTO: Decodable, Sendable {
    
    let info: Info
    let results: [CharacterDTO]
}

struct NamedResource: Decodable, Sendable { let name: String }

struct CharacterDTO: Decodable, Sendable {
    
    let id: Int
    let name: String
    let status: String
    let species: String
    let gender: String
    let origin: NamedResource
    let location: NamedResource
    let image: String
    let episode: [String]
}

struct EpisodeDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let airDate: String
    let episode: String
}

/// `/episode/1` returns an object while `/episode/1,2` returns an array. Handle both.
struct EpisodeListDTO: Decodable, Sendable {
    let episodes: [EpisodeDTO]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let many = try? container.decode([EpisodeDTO].self) {
            episodes = many
        } else {
            episodes = [try container.decode(EpisodeDTO.self)]
        }
    }
}

extension RMCharacter {
    init(dto: CharacterDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            status: CharacterStatus(apiValue: dto.status),
            species: dto.species,
            gender: dto.gender,
            originName: dto.origin.name,
            locationName: dto.location.name,
            imageURL: URL(string: dto.image),
            episodeIDs: dto.episode
                .compactMap { URL(string: $0)?.lastPathComponent }
                .compactMap(Int.init)
        )
    }
}

extension Episode {
    init(dto: EpisodeDTO) {
        self.init(id: dto.id, name: dto.name, airDate: dto.airDate, code: dto.episode)
    }
}
