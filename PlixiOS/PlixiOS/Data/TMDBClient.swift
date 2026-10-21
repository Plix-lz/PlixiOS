import Foundation

/// Port de TmdbClient (Android). Catálogo libre: todo lo que TMDB devuelve se muestra.
actor TMDBClient {
    static let shared = TMDBClient()

    static let apiBase = "https://api.themoviedb.org/3"
    static let imageBase = "https://image.tmdb.org/t/p/"
    static let sectionSize = 15
    static let suggestionsSize = 18
    static let relatedSize = 12
    static let searchSize = 120
    static let maxCatalogPages = 25
    static let premiereYear = 2026
    static let minVotes = 20
    static let minPopularity = 3.0
    static let minVotesRecent = 2
    static let recentWindowMs: Int64 = 45 * 24 * 60 * 60 * 1000
    static let videoLanguages =
        "es-MX,es,en,pt,fr,de,it,ja,ko,zh,hi,ru,ar,th,tr,pl,nl,sv,da,no,fi,id,vi,cs,hu,el,he,uk,ro,null"
    static let streamingSorts = ["popularity.desc", "vote_count.desc", "vote_average.desc"]
    static let hostTreeURL = "https://api.github.com/repos/thexxx880/apple/git/trees/main?recursive=1"
    static let serieJSONBase = "https://raw.githubusercontent.com/thexxx880/apple/main/data%20base/data/serie/"

    private var varietySeed = 0
    private var logoCache: [String: String] = [:]
    private var genreCache: [GenreEntry]?
    private var alternativeTitles: [String: [String]] = [:]
    private var hostMovies: [Int] = []
    private var hostSeries: [Int] = []
    private var hostSeasons: [Int: Set<Int>] = [:]
    private var hostLoadedAt: Int64 = 0

    private var apiKey: String { AppConfig.tmdbApiKey }

    static func imageURL(_ size: String, _ path: String) -> String {
        path.isEmpty ? "" : imageBase + size + path
    }

    // MARK: Peticiones base

    private func url(_ path: String, _ extraQuery: String?, page: Int? = nil, language: Bool = true) throws -> String {
        guard !apiKey.isEmpty else { throw PlixError.missingApiKey }
        var result = Self.apiBase + path + "?api_key=" + apiKey
        if language { result += "&language=es-MX" }
        if let page { result += "&include_adult=false&page=\(page)" }
        if let extraQuery, !extraQuery.isEmpty { result += "&" + extraQuery }
        return result
    }

    private func fetchPaged(_ path: String, _ query: String?, page: Int) async throws -> JSONObject {
        try await HTTP.json(try url(path, query, page: page), timeout: 15)
    }

    func prepareHomeRefresh() {
        varietySeed = (varietySeed + 1) % 5
    }

    var trendingWindow: String { varietySeed % 2 == 0 ? "day" : "week" }

    private func sectionStartPage(ranked: Bool) -> Int {
        ranked ? 1 : 1 + (varietySeed % 3)
    }

    private func streamingQuery() -> String {
        "watch_region=MX&with_watch_monetization_types=flatrate&sort_by=" +
            Self.streamingSorts[varietySeed % Self.streamingSorts.count]
    }

    static func discoverQuery(_ genres: String, sort: String = "popularity.desc", minVotes: Int = 1) -> String {
        "with_genres=\(genres)&sort_by=\(sort)&vote_count.gte=\(max(1, minVotes))"
    }

    // MARK: Parseo

    nonisolated static func text(_ object: JSONObject, _ first: String, _ second: String? = nil) -> String {
        let value = object.str(first).trimmingCharacters(in: .whitespaces)
        if !value.isEmpty, value.lowercased() != "null" { return value }
        guard let second else { return "" }
        let alt = object.str(second).trimmingCharacters(in: .whitespaces)
        return alt.lowercased() == "null" ? "" : alt
    }

    nonisolated static func parseItem(_ object: JSONObject, sourcePath: String) -> MediaItem? {
        var mediaType = text(object, "media_type")
        if mediaType == "person" { return nil }
        let title = text(object, "title", "name")
        var original = text(object, "original_title", "original_name")
        if original.isEmpty { original = title }
        let poster = text(object, "poster_path")
        if title.isEmpty || poster.isEmpty { return nil }
        if mediaType.isEmpty { mediaType = sourcePath.contains("/tv") ? "tv" : "movie" }
        var date = text(object, "release_date")
        if date.isEmpty { date = text(object, "first_air_date") }
        let year = date.count >= 4 ? String(date.prefix(4)) : ""
        let genres = (object["genre_ids"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }.filter { $0 > 0 } ?? []
        return MediaItem(
            id: object.int("id"), title: title, originalTitle: original, overview: text(object, "overview"),
            posterUrl: imageURL("w342", poster), backdropUrl: imageURL("w1280", text(object, "backdrop_path")),
            year: year, rating: object.double("vote_average"), mediaType: mediaType == "tv" ? .tv : .movie,
            genreIds: genres
        )
    }

    nonisolated static func isReleased(_ object: JSONObject) -> Bool {
        var date = text(object, "release_date")
        if date.isEmpty { date = text(object, "first_air_date") }
        return date.count >= 10 && String(date.prefix(10)) <= Clock.todayISO()
    }

    nonisolated static func looksReal(_ object: JSONObject) -> Bool {
        if text(object, "backdrop_path").isEmpty || text(object, "overview").isEmpty { return false }
        let votes = object.int("vote_count")
        let popularity = object.double("popularity")
        if votes >= minVotes && popularity >= minPopularity { return true }
        var date = text(object, "release_date")
        if date.isEmpty { date = text(object, "first_air_date") }
        return votes >= minVotesRecent && isRecent(date)
    }

    nonisolated static func isRecent(_ date: String) -> Bool {
        guard date.count >= 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: String(date.prefix(10))) else { return false }
        return Clock.nowMs - Int64(parsed.timeIntervalSince1970 * 1000) <= recentWindowMs
    }

    nonisolated static func parseReleased(_ object: JSONObject, sourcePath: String) -> MediaItem? {
        isReleased(object) && looksReal(object) ? parseItem(object, sourcePath: sourcePath) : nil
    }

    nonisolated static func parseResults(_ response: JSONObject, path: String) -> [MediaItem] {
        response.objects("results").compactMap { parseReleased($0, sourcePath: path) }
    }

    // MARK: Secciones del Home

    func homeSections() -> [HomeSection] {
        [
            HomeSection(id: "trending", title: "Tendencias", kind: .list(path: "/trending/all/\(trendingWindow)", query: "", mixWith: nil), ranked: true),
            HomeSection(id: "premieres", title: "Estrenos", kind: .premieres, ranked: false),
            HomeSection(id: "suggestions", title: "Sugerencias", kind: .suggestions, ranked: false),
            HomeSection(id: "movies", title: "Películas", kind: .list(path: "/trending/movie/day", query: "", mixWith: nil), ranked: false),
            HomeSection(id: "series", title: "Series", kind: .list(path: "/trending/tv/day", query: "", mixWith: nil), ranked: false),
            HomeSection(id: "top", title: "Lo mejor valorado", kind: .list(path: "/movie/top_rated", query: "", mixWith: "/tv/top_rated"), ranked: false),
            HomeSection(id: "action", title: "Acción y Aventura", kind: .genreMix(movieGenres: "28,12", tvGenres: "10759"), ranked: false),
            HomeSection(id: "comedy", title: "Comedias", kind: .genreMix(movieGenres: "35", tvGenres: "35"), ranked: false),
            HomeSection(id: "horror", title: "Terror y Suspenso", kind: .genreMix(movieGenres: "27,53", tvGenres: "9648"), ranked: false),
            HomeSection(id: "scifi", title: "Ciencia Ficción", kind: .genreMix(movieGenres: "878", tvGenres: "10765"), ranked: false),
            HomeSection(id: "romance", title: "Romance", kind: .genreMix(movieGenres: "10749", tvGenres: "10749"), ranked: false),
            HomeSection(id: "drama", title: "Series de Drama", kind: .genreMix(movieGenres: nil, tvGenres: "18"), ranked: false),
            HomeSection(id: "family", title: "Para toda la familia", kind: .genreMix(movieGenres: "10751", tvGenres: "10751"), ranked: false),
            HomeSection(id: "docs", title: "Documentales", kind: .genreMix(movieGenres: "99", tvGenres: "99"), ranked: false)
        ]
    }

    func kidsSections() -> [HomeSection] {
        [
            HomeSection(id: "kids_family_movies", title: "Películas familiares", kind: .list(path: "/discover/movie", query: Self.discoverQuery("10751"), mixWith: nil), ranked: false),
            HomeSection(id: "kids_animation", title: "Animación", kind: .genreMix(movieGenres: "16", tvGenres: "16"), ranked: false),
            HomeSection(id: "kids_series", title: "Series infantiles", kind: .list(path: "/discover/tv", query: Self.discoverQuery("10762"), mixWith: nil), ranked: false),
            HomeSection(id: "kids_family_series", title: "Series para toda la familia", kind: .list(path: "/discover/tv", query: Self.discoverQuery("10751"), mixWith: nil), ranked: false)
        ]
    }

    /// Recolector con las mismas reglas que SectionProgressSink.
    private final class Sink {
        let limit: Int
        let exclude: RecommendationProfile?
        var seen = Set<Int>()
        var items: [MediaItem] = []
        init(limit: Int, exclude: RecommendationProfile?) { self.limit = limit; self.exclude = exclude }
        var isFull: Bool { items.count >= limit }
        func offer(_ item: MediaItem, _ filter: ((MediaItem) -> Bool)? = nil) {
            guard !isFull, !seen.contains(item.id) else { return }
            seen.insert(item.id)
            if let exclude, exclude.watched(item) { return }
            if let filter, !filter(item) { return }
            items.append(item)
        }
    }

    func loadSection(_ section: HomeSection, profile: RecommendationProfile) async throws -> [MediaItem] {
        let isSuggestions: Bool
        if case .suggestions = section.kind { isSuggestions = true } else { isSuggestions = false }
        let sink = Sink(limit: isSuggestions ? Self.suggestionsSize : Self.sectionSize,
                        exclude: isSuggestions ? profile : nil)
        switch section.kind {
        case .premieres:
            let today = Clock.todayISO()
            let year = Self.premiereYear
            try await fetchMixedPaged(
                moviePath: "/discover/movie",
                movieQuery: "primary_release_year=\(year)&primary_release_date.lte=\(today)&sort_by=primary_release_date.desc&vote_count.gte=\(Self.minVotesRecent)",
                tvPath: "/discover/tv",
                tvQuery: "first_air_date_year=\(year)&first_air_date.lte=\(today)&sort_by=first_air_date.desc&vote_count.gte=\(Self.minVotesRecent)",
                startPage: 1, filter: { $0.year == String(year) }, sink: sink)
        case .suggestions:
            try await fetchSuggestions(profile, sink: sink)
        case .trending:
            try await fetchSinglePaged("/trending/all/\(trendingWindow)", nil, startPage: 1, sink: sink)
        case .list(let path, let query, let mixWith):
            if let mixWith {
                try await fetchMixedPaged(moviePath: path, movieQuery: query, tvPath: mixWith, tvQuery: query,
                                          startPage: 1, filter: nil, sink: sink)
            } else {
                try await fetchSinglePaged(path, query, startPage: sectionStartPage(ranked: section.ranked || path.contains("/trending/")), sink: sink)
            }
        case .genreMix(let movieGenres, let tvGenres):
            try await fetchGenrePersonalized(movieGenres: movieGenres, tvGenres: tvGenres, profile: profile, sink: sink)
        }
        return sink.items
    }

    private func fetchSinglePaged(_ path: String, _ query: String?, startPage: Int, sink: Sink) async throws {
        var page = max(1, startPage)
        var fetched = 0
        var totalPages = Self.maxCatalogPages
        var wrapped = false
        while !sink.isFull && fetched < Self.maxCatalogPages {
            if page > totalPages {
                if !wrapped && startPage > 1 { page = 1; wrapped = true; continue }
                break
            }
            let response = try await fetchPaged(path, query, page: page)
            totalPages = max(1, response.int("total_pages", 1))
            let items = Self.parseResults(response, path: path)
            if items.isEmpty {
                if !wrapped && startPage > 1 && page >= startPage { page = 1; wrapped = true; fetched += 1; continue }
                break
            }
            for item in items where !sink.isFull { sink.offer(item) }
            page += 1
            fetched += 1
            if wrapped && page >= startPage { break }
        }
    }

    private func fetchMixedPaged(moviePath: String?, movieQuery: String?, tvPath: String?, tvQuery: String?,
                                 startPage: Int, filter: ((MediaItem) -> Bool)?, sink: Sink) async throws {
        var movieActive = !(moviePath ?? "").isEmpty
        var tvActive = !(tvPath ?? "").isEmpty
        var page = max(1, startPage)
        var fetched = 0
        var wrapped = false
        while !sink.isFull && fetched < Self.maxCatalogPages && (movieActive || tvActive) {
            var movies: [MediaItem] = []
            var shows: [MediaItem] = []
            if movieActive, let moviePath {
                let response = try await fetchPaged(moviePath, movieQuery, page: page)
                movies = Self.parseResults(response, path: moviePath)
                if page >= max(1, response.int("total_pages", 1)) { movieActive = false }
            }
            if tvActive, let tvPath {
                let response = try await fetchPaged(tvPath, tvQuery, page: page)
                shows = Self.parseResults(response, path: tvPath)
                if page >= max(1, response.int("total_pages", 1)) { tvActive = false }
            }
            interleave(shows: shows, movies: movies, limit: Int.max, filter: filter, sink: sink)
            page += 1
            fetched += 1
            if !movieActive && !tvActive {
                if !wrapped && startPage > 1 {
                    page = 1
                    wrapped = true
                    movieActive = !(moviePath ?? "").isEmpty
                    tvActive = !(tvPath ?? "").isEmpty
                    continue
                }
                break
            }
            if wrapped && page >= startPage { break }
        }
    }

    private func fetchMixedUntil(moviePath: String?, movieQuery: String?, tvPath: String?, tvQuery: String?,
                                 maxAccepted: Int, sink: Sink) async throws {
        if sink.isFull || sink.items.count >= maxAccepted { return }
        var movieActive = !(moviePath ?? "").isEmpty
        var tvActive = !(tvPath ?? "").isEmpty
        var page = 1
        var fetched = 0
        while !sink.isFull && sink.items.count < maxAccepted && fetched < Self.maxCatalogPages && (movieActive || tvActive) {
            var movies: [MediaItem] = []
            var shows: [MediaItem] = []
            if movieActive, let moviePath {
                let response = try await fetchPaged(moviePath, movieQuery, page: page)
                movies = Self.parseResults(response, path: moviePath)
                if page >= max(1, response.int("total_pages", 1)) { movieActive = false }
            }
            if tvActive, let tvPath {
                let response = try await fetchPaged(tvPath, tvQuery, page: page)
                shows = Self.parseResults(response, path: tvPath)
                if page >= max(1, response.int("total_pages", 1)) { tvActive = false }
            }
            interleave(shows: shows, movies: movies, limit: maxAccepted, filter: nil, sink: sink)
            page += 1
            fetched += 1
        }
    }

    private func interleave(shows: [MediaItem], movies: [MediaItem], limit: Int,
                            filter: ((MediaItem) -> Bool)?, sink: Sink) {
        var index = 0
        while !sink.isFull && sink.items.count < limit {
            var offered = false
            if index < shows.count { sink.offer(shows[index], filter); offered = true }
            if sink.isFull || sink.items.count >= limit { break }
            if index < movies.count { sink.offer(movies[index], filter); offered = true }
            if !offered { break }
            index += 1
        }
    }

    private func fetchSuggestions(_ profile: RecommendationProfile, sink: Sink) async throws {
        let movieGenres = profile.movieGenres
        let tvGenres = profile.tvGenres
        if !profile.isEmpty {
            try await fetchMixedUntil(
                moviePath: movieGenres.isEmpty ? nil : "/discover/movie",
                movieQuery: movieGenres.first.map { Self.discoverQuery(String($0)) },
                tvPath: tvGenres.isEmpty ? nil : "/discover/tv",
                tvQuery: tvGenres.first.map { Self.discoverQuery(String($0)) },
                maxAccepted: min(6, sink.limit), sink: sink)
            if !sink.isFull {
                try await fetchMixedUntil(
                    moviePath: movieGenres.isEmpty ? nil : "/discover/movie",
                    movieQuery: movieGenres.first.map { Self.discoverQuery(String($0), sort: "vote_average.desc", minVotes: 80) },
                    tvPath: tvGenres.isEmpty ? nil : "/discover/tv",
                    tvQuery: tvGenres.first.map { Self.discoverQuery(String($0), sort: "vote_average.desc", minVotes: 80) },
                    maxAccepted: min(10, sink.limit), sink: sink)
            }
            let maxGenres = max(movieGenres.count, tvGenres.count)
            var index = 1
            while index < maxGenres && !sink.isFull {
                let movieGenre = index < movieGenres.count ? movieGenres[index] : nil
                let tvGenre = index < tvGenres.count ? tvGenres[index] : nil
                try await fetchMixedUntil(
                    moviePath: movieGenre == nil ? nil : "/discover/movie",
                    movieQuery: movieGenre.map { Self.discoverQuery(String($0)) },
                    tvPath: tvGenre == nil ? nil : "/discover/tv",
                    tvQuery: tvGenre.map { Self.discoverQuery(String($0)) },
                    maxAccepted: min(sink.items.count + 3, sink.limit), sink: sink)
                index += 1
            }
            if !sink.isFull {
                try await fetchMixedPaged(
                    moviePath: movieGenres.isEmpty ? nil : "/discover/movie",
                    movieQuery: Self.discoverQuery(movieGenres.map(String.init).joined(separator: "|")),
                    tvPath: tvGenres.isEmpty ? nil : "/discover/tv",
                    tvQuery: Self.discoverQuery(tvGenres.map(String.init).joined(separator: "|")),
                    startPage: 1, filter: nil, sink: sink)
            }
        }
        if !sink.isFull {
            try await fetchMixedPaged(moviePath: "/discover/movie", movieQuery: streamingQuery(),
                                      tvPath: "/discover/tv", tvQuery: streamingQuery(),
                                      startPage: sectionStartPage(ranked: false), filter: nil, sink: sink)
        }
    }

    private func fetchGenrePersonalized(movieGenres: String?, tvGenres: String?, profile: RecommendationProfile,
                                        sink: Sink) async throws {
        let movieIds = Self.genreIds(movieGenres)
        let tvIds = Self.genreIds(tvGenres)
        let movieOr = movieIds.map(String.init).joined(separator: "|")
        let tvOr = tvIds.map(String.init).joined(separator: "|")
        let movieBoost = profile.movieGenres.first(where: { !movieIds.contains($0) })
        let tvBoost = profile.tvGenres.first(where: { !tvIds.contains($0) })
        if movieBoost != nil || tvBoost != nil {
            let useMovie = !movieOr.isEmpty && movieBoost != nil
            let useTv = !tvOr.isEmpty && tvBoost != nil
            try await fetchMixedPaged(
                moviePath: useMovie ? "/discover/movie" : nil,
                movieQuery: useMovie ? Self.discoverQuery("\(movieOr),\(movieBoost ?? 0)") : nil,
                tvPath: useTv ? "/discover/tv" : nil,
                tvQuery: useTv ? Self.discoverQuery("\(tvOr),\(tvBoost ?? 0)") : nil,
                startPage: 1, filter: nil, sink: sink)
        }
        if !sink.isFull {
            try await fetchMixedPaged(
                moviePath: movieOr.isEmpty ? nil : "/discover/movie",
                movieQuery: movieOr.isEmpty ? nil : Self.discoverQuery(movieOr),
                tvPath: tvOr.isEmpty ? nil : "/discover/tv",
                tvQuery: tvOr.isEmpty ? nil : Self.discoverQuery(tvOr),
                startPage: 1, filter: nil, sink: sink)
        }
    }

    private static func genreIds(_ raw: String?) -> [Int] {
        guard let raw else { return [] }
        var result: [Int] = []
        for token in raw.split(whereSeparator: { $0 == "," || $0 == "|" }) {
            if let id = Int(token.trimmingCharacters(in: .whitespaces)), id > 0, !result.contains(id) { result.append(id) }
        }
        return result
    }

    // MARK: Géneros

    func homeGenres() async throws -> [GenreEntry] {
        if let genreCache { return genreCache }
        let movieURL = try url("/genre/movie/list", nil)
        let tvURL = try url("/genre/tv/list", nil)
        async let movieList = HTTP.json(movieURL)
        async let tvList = HTTP.json(tvURL)
        let movies = try await movieList.objects("genres")
        let shows = try await tvList.objects("genres")
        let excludedIds: Set<Int> = [10763, 10766, 10767]
        let excludedKeys: Set<String> = ["news", "soap", "talk", "noticias", "telenovela"]
        var merged: [String: (name: String, movie: Int?, tv: Int?)] = [:]
        func add(_ genre: JSONObject, isMovie: Bool) {
            let id = genre.int("id")
            let name = genre.str("name").trimmingCharacters(in: .whitespaces)
            guard id > 0, !name.isEmpty, !excludedIds.contains(id) else { return }
            let key = TextUtil.compactSearch(name)
            guard !key.isEmpty, !excludedKeys.contains(key) else { return }
            var entry = merged[key] ?? (name: name, movie: nil, tv: nil)
            if isMovie { entry.movie = id } else { entry.tv = id }
            merged[key] = entry
        }
        movies.forEach { add($0, isMovie: true) }
        shows.forEach { add($0, isMovie: false) }
        let result = merged.map { GenreEntry(name: $0.value.name, key: $0.key, movieId: $0.value.movie, tvId: $0.value.tv) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        genreCache = result
        return result
    }

    /// Una página de un género: series y películas intercaladas (igual que GenresActivity).
    func genrePage(_ genre: GenreEntry, page: Int) async throws -> (items: [MediaItem], hasMore: Bool) {
        var movies: [MediaItem] = []
        var shows: [MediaItem] = []
        var hasMore = false
        if let movieId = genre.movieId {
            let response = try await fetchPaged("/discover/movie", Self.discoverQuery(String(movieId)), page: page)
            movies = Self.parseResults(response, path: "/discover/movie")
            hasMore = hasMore || page < min(500, response.int("total_pages", 1))
        }
        if let tvId = genre.tvId {
            let response = try await fetchPaged("/discover/tv", Self.discoverQuery(String(tvId)), page: page)
            shows = Self.parseResults(response, path: "/discover/tv")
            hasMore = hasMore || page < min(500, response.int("total_pages", 1))
        }
        var result: [MediaItem] = []
        for index in 0..<max(movies.count, shows.count) {
            if index < shows.count { result.append(shows[index]) }
            if index < movies.count { result.append(movies[index]) }
        }
        return (result, hasMore)
    }

    func discoverPage(path: String, query: String, page: Int) async throws -> (items: [MediaItem], totalPages: Int) {
        let response = try await fetchPaged(path, query, page: page)
        return (Self.parseResults(response, path: path), min(500, max(1, response.int("total_pages", 1))))
    }

    // MARK: Catálogo host (GitHub)

    /// IDs con carpeta en el repositorio host; solo IDs, los datos vienen de TMDB.
    func hostCatalog(_ type: MediaType) async throws -> [ContentRef] {
        try await ensureHostCatalog()
        let ids = type == .tv ? hostSeries : hostMovies
        return ids.map { ContentRef(id: $0, type: type.contentType) }
    }

    private func ensureHostCatalog() async throws {
        if !hostMovies.isEmpty, Clock.nowMs - hostLoadedAt < 60 * 60 * 1000 { return }
        let catalog = try await HTTP.json(Self.hostTreeURL, timeout: 30)
        if catalog.bool("truncated") { throw PlixError.message("El índice del host llegó incompleto") }
        var movies = Set<Int>()
        var series = Set<Int>()
        var seasons: [Int: Set<Int>] = [:]
        let moviePrefix = "data base/data/movie/"
        let seriesPrefix = "data base/data/serie/"
        for entry in catalog.objects("tree") where entry.str("type") == "tree" {
            let path = entry.str("path")
            if path.hasPrefix(moviePrefix) {
                let rest = String(path.dropFirst(moviePrefix.count))
                if !rest.contains("/"), let id = Int(rest) { movies.insert(id) }
            } else if path.hasPrefix(seriesPrefix) {
                let rest = String(path.dropFirst(seriesPrefix.count))
                let parts = rest.split(separator: "/")
                if parts.count == 1, let id = Int(parts[0]) { series.insert(id) }
                if parts.count == 2, let id = Int(parts[0]), parts[1].count >= 2,
                   parts[1].first == "t" || parts[1].first == "T",
                   let season = Int(parts[1].dropFirst()), season > 0 {
                    seasons[id, default: []].insert(season)
                }
            }
        }
        guard !movies.isEmpty, !series.isEmpty else { throw PlixError.message("El catálogo del host está vacío") }
        hostMovies = movies.sorted(by: >)
        hostSeries = series.sorted(by: >)
        hostSeasons = seasons
        hostLoadedAt = Clock.nowMs
    }

    func itemsByIds(_ refs: [ContentRef]) async -> [MediaItem] {
        var requests: [(Int, String, String)] = []
        for (index, ref) in refs.enumerated() where ref.id > 0 {
            let path = ref.type == ContentType.series ? "/tv/" : "/movie/"
            if let requestURL = try? url(path + String(ref.id), nil) { requests.append((index, requestURL, path)) }
        }
        return await withTaskGroup(of: (Int, MediaItem?).self) { group -> [MediaItem] in
            for (index, requestURL, path) in requests {
                group.addTask {
                    guard let object = try? await HTTP.json(requestURL) else { return (index, nil) }
                    return (index, TMDBClient.parseItem(object, sourcePath: path))
                }
            }
            var collected: [(Int, MediaItem)] = []
            for await (index, item) in group { if let item { collected.append((index, item)) } }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: Detalle

    func movieDetail(_ id: Int) async throws -> MovieDetail {
        let object = try await HTTP.json(try url("/movie/\(id)", "include_video_language=\(Self.videoLanguages)&append_to_response=credits,recommendations,similar,videos"))
        let release = Self.text(object, "release_date")
        var countries: [String] = []
        for country in object.objects("production_countries") {
            let name = country.str("name").isEmpty ? country.str("iso_3166_1") : country.str("name")
            if !name.isEmpty, !countries.contains(name) { countries.append(name) }
        }
        let credits = object.obj("credits") ?? [:]
        let director = credits.objects("crew").first(where: { $0.str("job") == "Director" })?.str("name") ?? ""
        var related = Self.related(from: object, selfId: id, type: .movie)
        if related.count < Self.relatedSize {
            related = await fillRelated(related, genres: object.objects("genres").map { $0.int("id") }, type: .movie, selfId: id)
        }
        return MovieDetail(
            id: id, title: Self.text(object, "title", "original_title"),
            originalTitle: Self.text(object, "original_title"),
            overview: Self.text(object, "overview"),
            posterUrl: Self.imageURL("w500", Self.text(object, "poster_path")),
            backdropUrl: Self.imageURL("w1280", Self.text(object, "backdrop_path")),
            year: release.count >= 4 ? String(release.prefix(4)) : "",
            rating: object.double("vote_average"), voteCount: object.int("vote_count"),
            runtimeMinutes: object.int("runtime"),
            genres: object.objects("genres").map { $0.str("name") }.filter { !$0.isEmpty },
            genreIds: object.objects("genres").map { $0.int("id") }.filter { $0 > 0 },
            countries: countries, director: director,
            languages: Self.languages(object), trailerKey: await resolveYoutubeKey("movie", id, object.obj("videos")),
            cast: Self.cast(credits), related: related)
    }

    func seriesDetail(_ id: Int) async throws -> SeriesDetail {
        let object = try await HTTP.json(try url("/tv/\(id)", "include_video_language=\(Self.videoLanguages)&append_to_response=credits,recommendations,similar,videos"))
        let firstAir = Self.text(object, "first_air_date")
        var countries: [String] = []
        for code in (object["origin_country"] as? [Any])?.compactMap({ $0 as? String }) ?? [] {
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !countries.contains(trimmed) { countries.append(trimmed) }
        }
        for country in object.objects("production_countries") {
            let name = country.str("name").isEmpty ? country.str("iso_3166_1") : country.str("name")
            if !name.isEmpty, !countries.contains(name) { countries.append(name) }
        }
        var seasons: [SeasonInfo] = object.objects("seasons").compactMap {
            let number = $0.int("season_number", -1)
            return number > 0 ? SeasonInfo(number: number, name: $0.str("name")) : nil
        }
        if let hostSeasonSet = hostSeasons[id] {
            let listed = Set(seasons.map(\.number))
            for number in hostSeasonSet.sorted() where !listed.contains(number) {
                seasons.append(SeasonInfo(number: number, name: ""))
            }
            seasons.sort { $0.number < $1.number }
        }
        var related = Self.related(from: object, selfId: id, type: .tv)
        if related.count < Self.relatedSize {
            related = await fillRelated(related, genres: object.objects("genres").map { $0.int("id") }, type: .tv, selfId: id)
        }
        let network = object.objects("networks").map { $0.str("name") }.first(where: { !$0.isEmpty }) ?? ""
        return SeriesDetail(
            id: id, title: Self.text(object, "name", "original_name"),
            originalTitle: Self.text(object, "original_name"),
            overview: Self.text(object, "overview"),
            posterUrl: Self.imageURL("w500", Self.text(object, "poster_path")),
            backdropUrl: Self.imageURL("w1280", Self.text(object, "backdrop_path")),
            year: firstAir.count >= 4 ? String(firstAir.prefix(4)) : "",
            rating: object.double("vote_average"), voteCount: object.int("vote_count"),
            seasonsCount: seasons.count,
            genres: object.objects("genres").map { $0.str("name") }.filter { !$0.isEmpty },
            genreIds: object.objects("genres").map { $0.int("id") }.filter { $0 > 0 },
            countries: countries,
            creators: object.objects("created_by").map { $0.str("name") }.filter { !$0.isEmpty },
            network: network, languages: Self.languages(object),
            trailerKey: await resolveYoutubeKey("tv", id, object.obj("videos")),
            cast: Self.cast(object.obj("credits") ?? [:]), seasons: seasons, related: related)
    }

    private static func languages(_ object: JSONObject) -> [String] {
        var names: [String] = []
        for language in object.objects("spoken_languages") {
            let name = language.str("name").isEmpty ? language.str("english_name") : language.str("name")
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func cast(_ credits: JSONObject) -> [CastMember] {
        var result: [CastMember] = []
        for person in credits.objects("cast") where result.count < 8 {
            let name = person.str("name")
            guard !name.isEmpty else { continue }
            result.append(CastMember(id: person.int("id"), name: name, character: person.str("character"),
                                     profileUrl: imageURL("w185", text(person, "profile_path"))))
        }
        return result
    }

    private static func related(from object: JSONObject, selfId: Int, type: MediaType) -> [MediaItem] {
        var seen = Set<Int>([selfId])
        var result: [MediaItem] = []
        let path = type == .movie ? "/movie" : "/tv"
        for key in ["recommendations", "similar"] {
            for entry in object.obj(key)?.objects("results") ?? [] where result.count < relatedSize {
                guard let item = parseReleased(entry, sourcePath: path), !seen.contains(item.id) else { continue }
                seen.insert(item.id)
                result.append(item)
            }
        }
        return result
    }

    private func fillRelated(_ current: [MediaItem], genres: [Int], type: MediaType, selfId: Int) async -> [MediaItem] {
        guard let genre = genres.first else { return current }
        var result = current
        var seen = Set(current.map(\.id) + [selfId])
        let path = type == .movie ? "/discover/movie" : "/discover/tv"
        for page in 1...3 where result.count < Self.relatedSize {
            guard let response = try? await fetchPaged(path, Self.discoverQuery(String(genre)), page: page) else { break }
            for item in Self.parseResults(response, path: path) where result.count < Self.relatedSize && !seen.contains(item.id) {
                seen.insert(item.id)
                result.append(item)
            }
        }
        return result
    }

    private func resolveYoutubeKey(_ mediaPath: String, _ id: Int, _ videos: JSONObject?) async -> String {
        let key = Self.selectYoutubeKey(videos)
        if !key.isEmpty || id <= 0 { return key }
        guard let requestURL = try? url("/\(mediaPath)/\(id)/videos", "include_video_language=\(Self.videoLanguages)", language: false),
              let response = try? await HTTP.json(requestURL) else { return "" }
        return Self.selectYoutubeKey(response)
    }

    static func selectYoutubeKey(_ videos: JSONObject?) -> String {
        guard let videos else { return "" }
        var bestKey = ""
        var bestScore = Int.min
        for video in videos.objects("results") {
            guard video.str("site").lowercased() == "youtube" else { continue }
            let key = video.str("key").trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            var score: Int
            switch video.str("type").lowercased() {
            case "trailer": score = 100
            case "teaser": score = 80
            case "clip": score = 70
            case "featurette": score = 50
            case "behind the scenes": score = 40
            case "bloopers": score = 30
            case "opening credits", "recap": score = 25
            default: score = 10
            }
            if video.bool("official") { score += 15 }
            let language = video.str("iso_639_1").lowercased()
            if language == "es" { score += 20 } else if language == "en" { score += 5 }
            if score > bestScore { bestScore = score; bestKey = key }
        }
        return bestKey
    }

    // MARK: Temporadas

    func seasonEpisodes(seriesId: Int, season: Int) async throws -> [EpisodeItem] {
        let seasonURL = try url("/tv/\(seriesId)/season/\(season)", nil)
        async let githubNumbers = Self.githubEpisodeNumbers(seriesId: seriesId, season: season)
        let response = try await HTTP.json(seasonURL)
        var episodes: [EpisodeItem] = response.objects("episodes").enumerated().map { index, episode in
            EpisodeItem(season: season, episode: episode.int("episode_number", index + 1), name: episode.str("name"),
                        overview: episode.str("overview"),
                        stillUrl: Self.imageURL("w500", Self.text(episode, "still_path")),
                        runtime: episode.int("runtime"))
        }
        let extra = await githubNumbers
        let listed = Set(episodes.map(\.episode))
        for number in extra.sorted() where !listed.contains(number) {
            episodes.append(EpisodeItem(season: season, episode: number, name: "Episodio \(number)", overview: "",
                                        stillUrl: "", runtime: 0))
        }
        return episodes.sorted { $0.episode < $1.episode }
    }

    /// Lee los números de episodio del JSON de temporada en GitHub (`capitulos` o raíz numérica).
    private nonisolated static func githubEpisodeNumbers(seriesId: Int, season: Int) async -> Set<Int> {
        let address = "\(Self.serieJSONBase)\(seriesId)/t\(season)/\(seriesId).json"
        guard let data = try? await HTTP.data(address, timeout: 10), let root = OrderedJSON.parse(data) else { return [] }
        let source = root["capitulos"].map { $0.isObject ? $0 : root } ?? root
        var numbers = Set<Int>()
        for (key, _) in source.entries {
            if let number = Int(key.trimmingCharacters(in: .whitespaces)), number > 0 { numbers.insert(number) }
        }
        return numbers
    }

    // MARK: Logos del hero

    func heroLogo(_ item: MediaItem) async -> String {
        let key = item.key
        if let cached = logoCache[key] { return cached }
        let path = item.mediaType == .tv ? "/tv/\(item.id)/images" : "/movie/\(item.id)/images"
        guard let requestURL = try? url(path, "include_image_language=es,en,null", language: false),
              let response = try? await HTTP.json(requestURL) else { return "" }
        let logos = response.objects("logos").filter { !$0.str("file_path").lowercased().hasSuffix(".svg") }
        var chosen = ""
        for language in ["es", "en", ""] {
            if let logo = logos.first(where: { Self.text($0, "iso_639_1") == language }) {
                chosen = Self.imageURL("w500", logo.str("file_path"))
                break
            }
        }
        logoCache[key] = chosen
        return chosen
    }

    // MARK: Búsqueda

    func search(_ query: String) async -> [MediaItem] {
        let variants = SearchMatcher.variants(query)
        try? await ensureHostCatalog()
        let hostMovieSet = Set(hostMovies)
        let hostSeriesSet = Set(hostSeries)
        var candidates: [String: MediaItem] = [:]
        var order: [String] = []
        for (index, variant) in variants.enumerated() where candidates.count < 250 {
            let pages = index == 0 ? 10 : 2
            for page in 1...pages {
                guard let response = try? await fetchPaged("/search/multi", "query=" + HTTP.encode(variant), page: page) else { break }
                for object in response.objects("results") {
                    guard let item = Self.parseItem(object, sourcePath: "/search/multi") else { continue }
                    let inHost = item.mediaType == .tv ? hostSeriesSet.contains(item.id) : hostMovieSet.contains(item.id)
                    guard inHost || (Self.isReleased(object) && Self.looksReal(object)) else { continue }
                    if candidates[item.key] == nil { candidates[item.key] = item; order.append(item.key) }
                }
                if page >= response.int("total_pages", 1) { break }
            }
        }
        await prefetchAlternativeTitles(query, keys: order, candidates: candidates)
        var scored: [(MediaItem, Double)] = []
        for key in order {
            guard let item = candidates[key] else { continue }
            var score = max(SearchMatcher.score(query, item.title), SearchMatcher.score(query, item.originalTitle))
            for alternative in alternativeTitles[key] ?? [] { score = max(score, SearchMatcher.score(query, alternative)) }
            if score >= 0.52 { scored.append((item, score)) }
        }
        scored.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.rating > $1.0.rating }
        return Array(scored.prefix(Self.searchSize).map(\.0))
    }

    /// Títulos alternativos de los candidatos más débiles (presupuesto de 30 consultas).
    private func prefetchAlternativeTitles(_ query: String, keys: [String], candidates: [String: MediaItem]) async {
        var budget = 30
        for key in keys where budget > 0 {
            guard alternativeTitles[key] == nil, let item = candidates[key] else { continue }
            let direct = max(SearchMatcher.score(query, item.title), SearchMatcher.score(query, item.originalTitle))
            if direct >= 0.52 { continue }
            budget -= 1
            let path = item.mediaType == .tv ? "/tv/\(item.id)/alternative_titles" : "/movie/\(item.id)/alternative_titles"
            guard let requestURL = try? url(path, nil, language: false),
                  let response = try? await HTTP.json(requestURL, timeout: 8) else { continue }
            let list = response.objects(item.mediaType == .tv ? "results" : "titles").map { $0.str("title") }.filter { !$0.isEmpty }
            alternativeTitles[key] = list
        }
    }
}

enum SearchMatcher {
    static func variants(_ query: String) -> [String] {
        var ordered: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !ordered.contains(trimmed) { ordered.append(trimmed) }
        }
        let clean = TextUtil.normalizeSearch(query)
        let compact = TextUtil.compactSearch(query)
        if clean.isEmpty && compact.isEmpty { return [] }
        add(query)
        add(clean)
        add(compact)
        let words = clean.isEmpty ? [] : clean.split(separator: " ").map(String.init)
        if !words.isEmpty {
            let singular = words.map { singularize($0) }.joined(separator: " ")
            let plural = words.map { pluralize($0) }.joined(separator: " ")
            add(singular)
            add(plural)
            add(singular.replacingOccurrences(of: " ", with: ""))
            add(plural.replacingOccurrences(of: " ", with: ""))
            if words.count > 1 {
                add(words.reversed().joined(separator: " "))
                add(singular.split(separator: " ").reversed().joined(separator: " "))
                for word in words where word.count >= 3 { add(word) }
            } else if clean.count >= 5 {
                add(String(clean.dropLast()))
            }
        }
        return Array(ordered.prefix(10))
    }

    static func isVowel(_ character: Character) -> Bool { "aeiou".contains(character) }

    static func singularize(_ word: String) -> String {
        let length = word.count
        if length > 4 && word.hasSuffix("ces") { return String(word.dropLast(3)) + "z" }
        if length > 4 && word.hasSuffix("es") {
            let root = String(word.dropLast(2))
            if let last = root.last, !isVowel(last) { return root }
        }
        if length > 3 && word.hasSuffix("s") {
            let chars = Array(word)
            if isVowel(chars[length - 2]) { return String(word.dropLast()) }
        }
        return word
    }

    static func pluralize(_ word: String) -> String {
        let singular = singularize(word)
        guard let last = singular.last else { return word }
        if last == "z" { return String(singular.dropLast()) + "ces" }
        return singular + (isVowel(last) ? "s" : "es")
    }

    static func score(_ query: String, _ candidate: String) -> Double {
        let normalizedQuery = TextUtil.normalizeSearch(query)
        let normalizedCandidate = TextUtil.normalizeSearch(candidate)
        let compactQuery = normalizedQuery.replacingOccurrences(of: " ", with: "")
        let compactCandidate = normalizedCandidate.replacingOccurrences(of: " ", with: "")
        if (normalizedQuery.isEmpty && compactQuery.isEmpty) || (normalizedCandidate.isEmpty && compactCandidate.isEmpty) { return 0 }
        if !compactQuery.isEmpty && compactQuery == compactCandidate { return 1.25 }
        if !normalizedQuery.isEmpty && normalizedCandidate == normalizedQuery { return 1.2 }
        if !compactQuery.isEmpty && compactCandidate.contains(compactQuery) { return 1.1 }
        if !normalizedQuery.isEmpty && normalizedCandidate.contains(normalizedQuery) { return 1.05 }
        let queryWords = (normalizedQuery.isEmpty ? compactQuery : normalizedQuery).split(separator: " ").map(String.init)
        let candidateWords = normalizedCandidate.isEmpty ? [compactCandidate] : normalizedCandidate.split(separator: " ").map(String.init)
        var total = 0.0
        for queryWord in queryWords {
            var best = 0.0
            let queryRoot = singularize(queryWord)
            for candidateWord in candidateWords {
                let candidateRoot = singularize(candidateWord)
                if queryRoot == candidateRoot { best = 1; break }
                best = max(best, similarity(queryRoot, candidateRoot))
            }
            if best < 1 && !compactCandidate.isEmpty { best = max(best, similarity(queryRoot, compactCandidate)) }
            total += best
        }
        let coverage = total / Double(max(1, queryWords.count))
        let balance = Double(min(queryWords.count, candidateWords.count)) / Double(max(1, max(queryWords.count, candidateWords.count)))
        var bonus = 0.0
        if !compactQuery.isEmpty && !compactCandidate.isEmpty { bonus = similarity(compactQuery, compactCandidate) * 0.18 }
        return min(1.2, coverage * 0.82 + balance * 0.1 + bonus)
    }

    static func similarity(_ first: String, _ second: String) -> Double {
        let longest = max(first.count, second.count)
        if longest == 0 { return 1 }
        if first.count >= 4 && (first.hasPrefix(second) || second.hasPrefix(first)) { return 0.82 }
        return 1 - Double(editDistance(first, second)) / Double(longest)
    }

    static func editDistance(_ first: String, _ second: String) -> Int {
        let a = Array(first)
        let b = Array(second)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for row in 1...a.count {
            var current = [row] + Array(repeating: 0, count: b.count)
            for column in 1...b.count {
                let substitution = a[row - 1] == b[column - 1] ? 0 : 1
                current[column] = min(current[column - 1] + 1, previous[column] + 1, previous[column - 1] + substitution)
            }
            previous = current
        }
        return previous[b.count]
    }
}
