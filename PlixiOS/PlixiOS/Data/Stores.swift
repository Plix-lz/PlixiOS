import Foundation

/// Almacenes locales. Usan los mismos nombres de archivo y claves que Android para que el
/// respaldo de Firestore sea intercambiable entre ambas plataformas.
private func prefs(_ name: String) -> Prefs { PrefsRegistry.shared.prefs(name) }

enum MyListStore {
    static let name = "plix_my_list"

    private static func key(_ type: MediaType) -> String { type == .movie ? "movie_ids" : "serie_ids" }

    static func contains(_ id: Int, _ type: MediaType) -> Bool {
        prefs(name).stringSet(key(type)).contains(String(id))
    }

    /// Devuelve el nuevo estado (true = agregado).
    @MainActor @discardableResult
    static func toggle(_ id: Int, _ type: MediaType) -> Bool {
        let store = prefs(name)
        var ids = store.stringSet(key(type))
        let added: Bool
        if ids.contains(String(id)) { ids.remove(String(id)); added = false } else { ids.insert(String(id)); added = true }
        store.setStringSet(key(type), ids)
        AchievementManager.shared.onMyListChanged(count: count)
        return added
    }

    static var count: Int {
        prefs(name).stringSet("movie_ids").count + prefs(name).stringSet("serie_ids").count
    }

    static func refs() -> [ContentRef] {
        let store = prefs(name)
        let movies = store.stringSet("movie_ids").compactMap(Int.init).sorted(by: >).map { ContentRef(id: $0, type: ContentType.movie) }
        let series = store.stringSet("serie_ids").compactMap(Int.init).sorted(by: >).map { ContentRef(id: $0, type: ContentType.series) }
        return movies + series
    }
}

/// Historial y recientes de Sala Virtual comparten formato (entries JSON, máx. 40, más reciente primero).
struct ContentEntriesStore {
    let name: String
    let tag: String
    static let maxEntries = 40

    static let history = ContentEntriesStore(name: "plix_content_history", tag: "Historial")
    static let salaVirtual = ContentEntriesStore(name: "plix_sala_virtual_recents", tag: "SalaVirtual")

    private func read() -> [JSONObject] {
        (JSONUtil.array(from: prefs(name).string("entries", "[]")) ?? []).compactMap { $0 as? JSONObject }
    }

    func record(_ item: MediaItem) {
        var entries = read().filter { !($0.int("id") == item.id && $0.str("contentType") == item.mediaType.contentType) }
        let entry: JSONObject = [
            "id": item.id, "tag": tag, "contentType": item.mediaType.contentType, "openedAt": Clock.nowMs,
            "title": item.title, "originalTitle": item.originalTitle, "overview": item.overview,
            "posterUrl": item.posterUrl, "backdropUrl": item.backdropUrl, "year": item.year, "rating": item.rating
        ]
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries { entries = Array(entries.prefix(Self.maxEntries)) }
        prefs(name).setString("entries", JSONUtil.string(entries))
    }

    func remove(_ item: MediaItem) {
        let entries = read().filter { !($0.int("id") == item.id && $0.str("contentType") == item.mediaType.contentType) }
        prefs(name).setString("entries", JSONUtil.string(entries))
    }

    func list() -> [MediaItem] {
        read().compactMap { entry in
            let id = entry.int("id")
            guard id > 0 else { return nil }
            return MediaItem(id: id, title: entry.str("title"), originalTitle: entry.str("originalTitle"),
                             overview: entry.str("overview"), posterUrl: entry.str("posterUrl"),
                             backdropUrl: entry.str("backdropUrl"), year: entry.str("year"),
                             rating: entry.double("rating"), mediaType: MediaType(contentType: entry.str("contentType")),
                             genreIds: [])
        }
    }

    func clear() { prefs(name).setString("entries", "[]") }
}

enum PlaybackProgressStore {
    static let name = "plix_playback_progress"

    static func movieKey(_ id: Int) -> String { "movie:\(id)" }
    static func episodeKey(_ id: Int, _ season: Int, _ episode: Int) -> String { "series:\(id):t\(season):e\(episode)" }
    private static func watchedKey(_ id: Int, _ season: Int, _ episode: Int) -> String { "watched:" + episodeKey(id, season, episode) }
    private static func lastEpisodeKey(_ id: Int, _ season: Int) -> String { "series:\(id):t\(season):last_episode" }

    static func position(_ key: String) -> Int64 { prefs(name).long(key) }
    static func savePosition(_ key: String, _ ms: Int64) { prefs(name).setLong(key, ms) }
    static func clearPosition(_ key: String) { prefs(name).remove(key) }

    static func setSelectedSeason(_ id: Int, _ season: Int) { prefs(name).setInt("series:\(id):selected_season", season) }
    static func selectedSeason(_ id: Int, fallback: Int) -> Int { prefs(name).int("series:\(id):selected_season", fallback) }

    static func markEpisodeStarted(_ id: Int, _ season: Int, _ episode: Int) {
        prefs(name).edit { values in
            values[watchedKey(id, season, episode)] = .bool(true)
            values[lastEpisodeKey(id, season)] = .int(episode)
            values["series:\(id):selected_season"] = .int(season)
        }
    }

    static func lastEpisode(_ id: Int, _ season: Int, fallback: Int) -> Int {
        prefs(name).int(lastEpisodeKey(id, season), fallback)
    }

    static func watchedEpisodes(_ id: Int, _ season: Int) -> Set<Int> {
        let prefix = "watched:series:\(id):t\(season):e"
        var result = Set<Int>()
        for (key, value) in prefs(name).snapshot() where key.hasPrefix(prefix) {
            if case .bool(true) = value, let number = Int(key.dropFirst(prefix.count)) { result.insert(number) }
        }
        return result
    }

    static func markContentStarted(_ id: Int, series: Bool) {
        prefs(name).setBool("started:" + (series ? "series:" : "movie:") + String(id), true)
    }

    static func hasProgress(_ item: MediaItem) -> Bool {
        let snapshot = prefs(name).snapshot()
        if item.mediaType == .movie {
            if case .bool(true)? = snapshot["started:movie:\(item.id)"] { return true }
            if case .long(let value)? = snapshot[movieKey(item.id)], value > 0 { return true }
            return false
        }
        if case .bool(true)? = snapshot["started:series:\(item.id)"] { return true }
        let prefix = "series:\(item.id):t"
        return snapshot.contains { key, value in
            guard key.hasPrefix(prefix), key.contains(":e") else { return false }
            if case .long(let position) = value { return position > 0 }
            return false
        }
    }
}

enum GenreTasteStore {
    static let name = "plix_genre_taste"
    private static let dayMs: Int64 = 24 * 60 * 60 * 1000

    static func record(_ type: MediaType, genreIds: [Int]) {
        guard !genreIds.isEmpty else { return }
        let store = prefs(name)
        var stored = JSONUtil.object(from: store.string("genre_counts", "{}")) ?? [:]
        let now = Clock.nowMs
        for genre in genreIds where genre > 0 {
            let key = "\(type == .tv ? "tv" : "movie"):\(genre)"
            let previous = stored[key] as? JSONObject
            stored[key] = ["count": (previous?.int("count") ?? 0) + 1, "lastAt": now]
        }
        store.setString("genre_counts", JSONUtil.string(stored))
    }

    static func profile() -> RecommendationProfile {
        let stored = JSONUtil.object(from: prefs(name).string("genre_counts", "{}")) ?? [:]
        var movies: [(Int, Double)] = []
        var shows: [(Int, Double)] = []
        let now = Clock.nowMs
        for (key, raw) in stored {
            guard let entry = raw as? JSONObject else { continue }
            let parts = key.split(separator: ":")
            guard parts.count == 2, let id = Int(parts[1]), id > 0 else { continue }
            let score = Double(max(1, entry.int("count", 1))) * recencyWeight(now - entry.int64("lastAt"))
            if parts[0] == "tv" { shows.append((id, score)) } else { movies.append((id, score)) }
        }
        var movieIds = top(movies)
        var tvIds = top(shows)
        if tvIds.isEmpty && !movieIds.isEmpty {
            tvIds = unique(movieIds.map(movieToTv))
        } else if movieIds.isEmpty && !tvIds.isEmpty {
            movieIds = unique(tvIds.map(tvToMovie))
        }
        let watched = Set(ContentEntriesStore.history.list().map(\.id))
        return RecommendationProfile(movieGenres: movieIds, tvGenres: tvIds, watchedIds: watched)
    }

    private static func recencyWeight(_ age: Int64) -> Double {
        if age < 0 { return 1.4 }
        if age <= 7 * dayMs { return 1.5 }
        if age <= 30 * dayMs { return 1.0 }
        if age <= 90 * dayMs { return 0.6 }
        return 0.3
    }

    private static func top(_ scored: [(Int, Double)]) -> [Int] {
        unique(scored.sorted { $0.1 > $1.1 }.map(\.0)).prefix(4).map { $0 }
    }

    private static func unique(_ values: [Int]) -> [Int] {
        var result: [Int] = []
        for value in values where value > 0 && !result.contains(value) { result.append(value) }
        return result
    }

    static func movieToTv(_ id: Int) -> Int {
        switch id {
        case 28, 12: return 10759
        case 878, 14: return 10765
        case 27, 53: return 9648
        default: return id
        }
    }

    static func tvToMovie(_ id: Int) -> Int {
        switch id {
        case 10759: return 28
        case 10765: return 878
        case 9648: return 53
        case 10762: return 10751
        default: return id
        }
    }
}

enum HeaderLogoStore {
    static let name = "plix_header_logo"
    static let defaultLogo = "default"
    static let lzPlay = "lzplay"

    static var selected: String {
        let value = prefs(name).string("selected", defaultLogo)
        if value == lzPlay && !AchievementStore.isUnlocked("lz_play") { return defaultLogo }
        return value
    }

    static func select(_ value: String) { prefs(name).setString("selected", value) }
}

enum AppUsageStore {
    static let name = "plix_app_usage"

    static var totalMs: Int64 { prefs(name).long("total_ms") }

    static func add(_ ms: Int64, userKey: String) {
        guard ms > 0 else { return }
        let store = prefs(name)
        let current = store.optionalString("user_key")
        let base = current == nil || current == userKey ? store.long("total_ms") : 0
        store.edit { values in
            values["total_ms"] = .long(base + ms)
            values["user_key"] = .string(userKey)
        }
    }
}

/// Avatar y fondo del perfil (mismas claves: folder, pack, id, extension, updated_at).
struct ProfileImageStore {
    let name: String
    static let avatar = ProfileImageStore(name: "plix_profile_avatar")
    static let backdrop = ProfileImageStore(name: "plix_profile_backdrop")

    var current: AvatarRef? {
        let store = prefs(name)
        let id = store.string("id")
        guard !id.isEmpty else { return nil }
        return AvatarRef(folder: store.string("folder"), pack: store.string("pack"), id: id, ext: store.string("extension"))
    }

    var updatedAt: Int64 { prefs(name).long("updated_at") }

    func save(_ ref: AvatarRef, updatedAt: Int64 = Clock.nowMs) {
        prefs(name).edit { values in
            values["folder"] = .string(ref.folder)
            values["pack"] = .string(ref.pack)
            values["id"] = .string(ref.id)
            values["extension"] = .string(ref.ext)
            values["updated_at"] = .long(updatedAt)
        }
    }

    func clear() { prefs(name).clear() }
}

enum StickerStore {
    static let name = "plix_chat_stickers"
    static let maxSelected = 20

    static var selected: [String] {
        (JSONUtil.array(from: prefs(name).string("sticker_ids", "[]")) ?? []).compactMap { $0 as? String }
    }

    static func save(_ ids: [String]) {
        prefs(name).setString("sticker_ids", JSONUtil.string(Array(ids.prefix(maxSelected))))
    }
}

enum ProfileBioStore {
    static let name = "plix_profile_bio"
    static let maxLength = 150

    static var text: String { prefs(name).string("text") }
    static var updatedAt: Int64 { prefs(name).long("updated_at") }

    static func save(_ value: String) {
        let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        prefs(name).edit { values in
            values["text"] = .string(trimmed)
            values["updated_at"] = .long(Clock.nowMs)
        }
    }
}

enum PlayerUIStore {
    static let name = "plix_player_ui"
    static var brightness: Double { prefs(name).float("player_brightness", -1) }
    static func setBrightness(_ value: Double) { prefs(name).setFloat("player_brightness", value) }
}
