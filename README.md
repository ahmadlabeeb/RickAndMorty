# Rick & Morty – iOS Technical Assessment

A SwiftUI app to browse Rick & Morty characters (paginated, searchable, filterable) and view details with lazily loaded episodes. Built with Swift 6, iOS 26, MVVM + Repository pattern, Swift Concurrency, SwiftData and a custom image cache. **No third-party dependencies.**

## Setup

| Requirement | Version |
|---|---|
| Xcode | 27.1 or later (stable) |
| iOS deployment target | 26.2 |
| Swift | 6.4 (strict concurrency / Swift 6 language mode) |

Open `RickAndMorty.xcodeproj` in Xcode:

```bash
open RickAndMorty.xcodeproj
```

Then pick an iOS simulator (iOS 26.2 or later) and press **⌘R** to run or **⌘U** to run the tests. No API key is needed.

## Architecture

**MVVM + Repository**, with a small composition root for dependency injection.

```
View (SwiftUI) → ViewModel (@Observable, @MainActor) → Repository (protocol) → APIClient (protocol) / Cache (protocol)
```

```
RickAndMorty/
├── App/                      Entry point + AppContainer (composition root / DI)
├── Core/
│   ├── Networking/           APIClient, Endpoint, NetworkError
│   └── Images/               ImageLoader (actor) + memory cache + CachedAsyncImage
├── Domain/                   Pure models: RMCharacter, Episode, CharacterQuery, CharactersPage
├── Data/
│   ├── DTO.swift             API response types + mapping to domain
│   ├── Repositories.swift    Character & Episode repositories
│   └── Persistence/          SwiftData cache (@ModelActor)
└── Features/
    ├── CharacterList/        View + ViewModel
    └── CharacterDetail/      View + ViewModel
RickAndMortyTests/            Swift Testing unit tests + mocks
```

### Key decisions and trade-offs

- **Layers depend on protocols** (`APIClient`, `CharacterRepository`, `EpisodeRepository`, `CharacterCache`, `ImageLoading`), so each layer is tested in isolation with mocks.
- **Swift 6 concurrency**: view models are `@MainActor`; the image loader, SwiftData cache and episode repository are `actor`s; models and DTOs are `Sendable` value types.
- **State is an explicit enum** (`idle / loading / loaded / empty / error`), plus separate flags (`isPaginating`, `isRefreshing`) so a pagination or refresh failure never wipes content already on screen.
- **Stale-response protection**: every reload bumps a generation counter. Late responses from superseded requests (e.g. while typing in search) are discarded.
- **Pagination**: next page loads when one of the last 5 rows appears; a guard prevents concurrent page loads; characters are de-duplicated by `id` using a `Set`.
- **Search / filter / sort**: search (debounced 400 ms) and status filter are sent to the API, so pagination stays correct. Sorting is local because the API has no sort parameter.
- **Episodes**: loaded only when the details screen appears. Episode IDs are parsed from the URLs and fetched in **one batched request** (`/episode/1,2,3`). The repository caches episodes in memory and only requests the ones it doesn't have.
- **Persistence (SwiftData)**: unfiltered character pages are cached. If the network is down (offline/timeout) the repository serves cached pages and the UI shows an "offline" banner. Filtered/searched results are not cached on purpose.
- **Image caching**: custom `ImageLoader` actor with an `NSCache` (cost-limited, evicts under memory pressure), in-flight request de-duplication, background decoding via `preparingForDisplay()`, and a synchronous cache lookup so cached images don't flash a placeholder. HTTP-level disk caching comes from `URLSession`'s default `URLCache`.
- **Accessibility**: Dynamic Type (semantic fonts, `@ScaledMetric`), row elements are combined for VoiceOver with hints, decorative images are hidden, status is conveyed by text and not colour alone, headers have the header trait.
- **Dark mode / iPad**: system colours throughout; details screen is width-constrained for large screens.

### Dependency injection

Constructor injection everywhere. `AppContainer` is the only place that knows concrete types. It builds the repositories and exposes factory methods (`makeCharacterListViewModel()`, `makeCharacterDetailViewModel(for:)`). Images are injected via a SwiftUI `Environment` value (`\.imageLoader`).

## Testing

Run with **⌘U**. Uses the Swift Testing framework (`@Test`, `#expect`).

| Area | What is covered |
|---|---|
| Networking | Decoding, URL/query building, 404, 5xx, empty body, malformed JSON, offline, timeout (via `URLProtocol` stub) |
| Image loading | Memory cache hit, concurrent request sharing, invalid data |
| Repositories | DTO → domain mapping, endpoint used, caching rules, 404 → empty page, offline fallback, batching and caching of episodes |
| Persistence | SwiftData round trip and upsert (in-memory store) |
| ViewModels | Initial load, empty, error + retry, pagination, de-duplication, concurrent-load coalescing, pagination/refresh failures, search debounce, filter, sort, stale responses, lazy episode loading |

## Assumptions

- The API returns HTTP 404 for "no results", so that is treated as an empty state and not an error.
- Episode air dates are displayed as returned by the API (already human readable).
- Only the unfiltered list is cached for offline use. Episodes are cached in memory only, so opening a character's episodes offline for the first time shows an error with a retry button.
- Sorting applies to the characters loaded so far.
- The domain type is called `RMCharacter` to avoid shadowing Swift's `Character`.

## Possible improvements

- Persist episodes and a disk image cache for full offline details.
- UI and snapshot tests.
- Recently-viewed characters (the SwiftData model already supports adding it).
