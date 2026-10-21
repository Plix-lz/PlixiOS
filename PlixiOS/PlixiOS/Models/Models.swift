import Foundation

enum MediaType: String, Codable, Hashable {
    case movie
    case tv

    /// Tipo usado en historial, Mi lista y Firestore ("movie" / "series").
    var contentType: String { self == .movie ? ContentType.movie : ContentType.series }
    var label: String { self == .movie ? "Película" : "Serie" }

    init(contentType: String) {
        self = contentType == ContentType.series || contentType == "tv" ? .tv : .movie
    }
}

enum ContentType {
    static let movie = "movie"
    static let series = "series"
}

struct MediaItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let originalTitle: String
    let overview: String
    let posterUrl: String
    let backdropUrl: String
    let year: String
    let rating: Double
    let mediaType: MediaType
    let genreIds: [Int]

    var key: String { "\(mediaType.rawValue):\(id)" }
    var ratingText: String { rating > 0 ? String(format: "%.1f", rating) : "N/D" }
    var yearText: String { year.isEmpty ? "—" : year }
}

struct ContentRef: Hashable {
    let id: Int
    let type: String
}

struct CastMember: Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String
    let profileUrl: String
}

struct MovieDetail {
    let id: Int
    let title: String
    let originalTitle: String
    let overview: String
    let posterUrl: String
    let backdropUrl: String
    let year: String
    let rating: Double
    let voteCount: Int
    let runtimeMinutes: Int
    let genres: [String]
    let genreIds: [Int]
    let countries: [String]
    let director: String
    let languages: [String]
    let trailerKey: String
    let cast: [CastMember]
    let related: [MediaItem]

    var asMediaItem: MediaItem {
        MediaItem(id: id, title: title, originalTitle: originalTitle, overview: overview, posterUrl: posterUrl,
                  backdropUrl: backdropUrl, year: year, rating: rating, mediaType: .movie, genreIds: genreIds)
    }
}

struct SeasonInfo: Hashable, Identifiable {
    let number: Int
    let name: String
    var id: Int { number }
}

struct SeriesDetail {
    let id: Int
    let title: String
    let originalTitle: String
    let overview: String
    let posterUrl: String
    let backdropUrl: String
    let year: String
    let rating: Double
    let voteCount: Int
    let seasonsCount: Int
    let genres: [String]
    let genreIds: [Int]
    let countries: [String]
    let creators: [String]
    let network: String
    let languages: [String]
    let trailerKey: String
    let cast: [CastMember]
    let seasons: [SeasonInfo]
    let related: [MediaItem]

    var asMediaItem: MediaItem {
        MediaItem(id: id, title: title, originalTitle: originalTitle, overview: overview, posterUrl: posterUrl,
                  backdropUrl: backdropUrl, year: year, rating: rating, mediaType: .tv, genreIds: genreIds)
    }
}

struct EpisodeItem: Identifiable, Hashable {
    let season: Int
    let episode: Int
    let name: String
    let overview: String
    let stillUrl: String
    let runtime: Int
    var id: String { "t\(season)e\(episode)" }
}

struct StreamServer: Identifiable, Hashable {
    let name: String
    let url: String
    let directStream: Bool
    let language: String
    var id: String { url.lowercased() }
}

struct GenreEntry: Identifiable, Hashable {
    let name: String
    let key: String
    let movieId: Int?
    let tvId: Int?
    var id: String { key }
}

/// Sección del Home / categorías. Las consultas se arman igual que en TmdbClient.Section.
struct HomeSection: Identifiable, Hashable {
    enum Kind: Hashable {
        case trending
        case premieres
        case suggestions
        case list(path: String, query: String, mixWith: String?)
        case genreMix(movieGenres: String?, tvGenres: String?)
    }

    let id: String
    let title: String
    let kind: Kind
    let ranked: Bool
}

struct RecommendationProfile {
    let movieGenres: [Int]
    let tvGenres: [Int]
    let watchedIds: Set<Int>

    static let empty = RecommendationProfile(movieGenres: [], tvGenres: [], watchedIds: [])

    var isEmpty: Bool { movieGenres.isEmpty && tvGenres.isEmpty }

    func watched(_ item: MediaItem) -> Bool { watchedIds.contains(item.id) }
}

struct AvatarRef: Hashable, Codable {
    let folder: String
    let pack: String
    let id: String
    let ext: String

    var isEmpty: Bool { id.isEmpty }

    var dictionary: JSONObject { ["folder": folder, "pack": pack, "id": id, "extension": ext] }

    init(folder: String, pack: String, id: String, ext: String) {
        self.folder = folder
        self.pack = pack
        self.id = id
        self.ext = ext
    }

    init?(dictionary: JSONObject?) {
        guard let dictionary, !dictionary.str("id").isEmpty else { return nil }
        folder = dictionary.str("folder")
        pack = dictionary.str("pack")
        id = dictionary.str("id")
        ext = dictionary.str("extension")
    }
}
