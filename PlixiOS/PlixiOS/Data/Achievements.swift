import AVFoundation
import Foundation

enum AchievementCategory: String, CaseIterable {
    case explorer, collector, experience, constancy, secret

    var title: String {
        switch self {
        case .explorer: return "Explorador"
        case .collector: return "Coleccionista"
        case .experience: return "Experiencia"
        case .constancy: return "Constancia"
        case .secret: return "Lo que no debería estar aquí"
        }
    }

    var emoji: String {
        switch self {
        case .explorer: return "🎬"
        case .collector: return "❤️"
        case .experience: return "🔥"
        case .constancy: return "🌟"
        case .secret: return "👁️"
        }
    }
}

struct Achievement: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let category: AchievementCategory
    let emoji: String
    let required: Int
    let secret: Bool
    var progress = 0
    var unlocked = false
    var unlockedAtMs: Int64 = 0

    static let all: [Achievement] = [
        Achievement(id: "first_play", name: "Primera reproducción", description: "Reproduce tu primer contenido.", category: .explorer, emoji: "🎬", required: 1, secret: false),
        Achievement(id: "getting_started", name: "Comenzamos", description: "Disfruta de 3 contenidos diferentes.", category: .explorer, emoji: "🍿", required: 3, secret: false),
        Achievement(id: "cinephile", name: "Cinéfilo", description: "Mira 10 películas diferentes.", category: .explorer, emoji: "🎥", required: 10, secret: false),
        Achievement(id: "episode_watcher", name: "Maratonista", description: "Mira 10 episodios diferentes.", category: .explorer, emoji: "📺", required: 10, secret: false),
        Achievement(id: "vip", name: "VIP del contenido", description: "Has visto una gran cantidad de contenido.", category: .explorer, emoji: "💎", required: 50, secret: false),
        Achievement(id: "legend", name: "Leyenda", description: "Te has convertido en un verdadero experto.", category: .explorer, emoji: "👑", required: 100, secret: false),
        Achievement(id: "collector", name: "Coleccionista", description: "Agrega 5 contenidos a Mi Lista.", category: .collector, emoji: "❤️", required: 5, secret: false),
        Achievement(id: "favorite", name: "Mi favorita", description: "Agrega 10 contenidos a Mi Lista.", category: .collector, emoji: "⭐", required: 10, secret: false),
        Achievement(id: "completist", name: "Completista", description: "Termina una serie completa.", category: .collector, emoji: "🏆", required: 1, secret: false),
        Achievement(id: "cant_stop", name: "No puedo parar", description: "Mira 5 contenidos en un mismo día.", category: .experience, emoji: "🔥", required: 5, secret: false),
        Achievement(id: "one_more", name: "Uno más...", description: "No puedes dejar de mirar.", category: .experience, emoji: "👀", required: 3, secret: false),
        Achievement(id: "binge", name: "Maratón", description: "Disfruta de una gran maratón.", category: .experience, emoji: "🚀", required: 5, secret: false),
        Achievement(id: "night_owl", name: "Búho nocturno", description: "Disfruta de contenido durante la madrugada.", category: .experience, emoji: "🌙", required: 1, secret: false),
        Achievement(id: "early_bird", name: "Madrugador", description: "Empieza el día con algo para ver.", category: .experience, emoji: "☀️", required: 1, secret: false),
        Achievement(id: "explorer", name: "Explorador", description: "Explora nuevos contenidos.", category: .constancy, emoji: "🔎", required: 10, secret: false),
        Achievement(id: "veteran", name: "Veterano", description: "Ya llevas tiempo disfrutando de la aplicación.", category: .constancy, emoji: "🏅", required: 7, secret: false),
        Achievement(id: "constant", name: "Constante", description: "Regresa durante varios días.", category: .constancy, emoji: "📅", required: 3, secret: false),
        Achievement(id: "streak", name: "En racha", description: "Mantén tu racha durante una semana.", category: .constancy, emoji: "🔥", required: 7, secret: false),
        Achievement(id: "all_terrain", name: "Todo terreno", description: "Explora diferentes géneros.", category: .constancy, emoji: "🎭", required: 5, secret: false),
        Achievement(id: "no_borders", name: "Sin fronteras", description: "Descubre contenido de diferentes países.", category: .constancy, emoji: "🌎", required: 3, secret: false),
        Achievement(id: "lz_play", name: "LzPlay", description: "Que hacias buscando esto?", category: .secret, emoji: "🗝️", required: 1, secret: true)
    ]
}

/// Mismas claves que AchievementStore (plix_achievements).
enum AchievementStore {
    static let name = "plix_achievements"
    private static var prefs: Prefs { PrefsRegistry.shared.prefs(name) }

    static func isUnlocked(_ id: String) -> Bool { prefs.stringSet("unlocked_ids").contains(id) }
    static var unlockedIds: Set<String> { prefs.stringSet("unlocked_ids") }
    static func unlockedAt(_ id: String) -> Int64 { prefs.long("unlocked_at:\(id)") }

    static func markUnlocked(_ id: String, at: Int64) {
        var ids = unlockedIds
        guard !ids.contains(id) else { return }
        ids.insert(id)
        prefs.edit { values in
            values["unlocked_ids"] = .stringSet(ids)
            values["unlocked_at:\(id)"] = .long(at)
        }
    }

    static func set(_ key: String) -> Set<String> { prefs.stringSet(key) }

    static func addToSet(_ key: String, _ value: String) {
        var current = prefs.stringSet(key)
        guard !current.contains(value) else { return }
        current.insert(value)
        prefs.setStringSet(key, current)
    }

    static func addAll(_ key: String, _ values: [String]) {
        var current = prefs.stringSet(key)
        let before = current.count
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { current.insert(trimmed) }
        }
        if current.count != before { prefs.setStringSet(key, current) }
    }

    static func episodeKey(_ id: Int, _ season: Int, _ episode: Int) -> String { "episode:\(id):t\(season):e\(episode)" }

    static var searchCount: Int { prefs.int("search_count") }
    static func incrementSearch() { prefs.setInt("search_count", searchCount + 1) }
    static var myListCount: Int { prefs.int("my_list_count") }
    static func setMyListCount(_ value: Int) { prefs.setInt("my_list_count", max(0, value)) }
    static var dayStreak: Int { prefs.int("day_streak") }
    static var lastOpenDay: String { prefs.string("last_open_day") }

    static func setDayStreak(_ streak: Int, day: String) {
        var days = prefs.stringSet("active_days")
        days.insert(day)
        prefs.edit { values in
            values["day_streak"] = .int(max(0, streak))
            values["last_open_day"] = .string(day)
            values["active_days"] = .stringSet(days)
        }
    }

    static var episodeStreak: Int { prefs.int("episode_streak") }
    static var lastEpisodeKey: String { prefs.string("last_episode_key") }

    static func setEpisodeStreak(_ streak: Int, key: String) {
        prefs.edit { values in
            values["episode_streak"] = .int(max(0, streak))
            values["last_episode_key"] = .string(key)
        }
    }

    static func flag(_ key: String) -> Bool { prefs.bool(key) }
    static func setFlag(_ key: String) { prefs.setBool(key, true) }

    static func contentsForDay(_ day: String) -> Int { dayContents(day).count }

    private static func dayContents(_ day: String) -> [String] {
        let root = JSONUtil.object(from: prefs.string("day_contents", "{}")) ?? [:]
        return (root[day] as? [Any])?.compactMap { $0 as? String }.filter { !$0.isEmpty } ?? []
    }

    static func addContentForDay(_ day: String, _ key: String) {
        var root = JSONUtil.object(from: prefs.string("day_contents", "{}")) ?? [:]
        var values = dayContents(day)
        if !values.contains(key) { values.append(key) }
        root[day] = values
        if root.count > 21 {
            for oldKey in root.keys.sorted().prefix(root.count - 21) { root.removeValue(forKey: oldKey) }
        }
        prefs.setString("day_contents", JSONUtil.string(root))
    }

    static func cacheMeta(_ id: Int, series: Bool, genres: [String], origins: [String]) {
        let key = (series ? "series:" : "movie:") + String(id)
        prefs.edit { values in
            let cleanGenres = genres.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let cleanOrigins = origins.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !cleanGenres.isEmpty { values["meta_genres:" + key] = .string(cleanGenres.joined(separator: "|")) }
            if !cleanOrigins.isEmpty { values["meta_origins:" + key] = .string(cleanOrigins.joined(separator: "|")) }
        }
    }

    static func cachedMeta(_ prefix: String, _ id: Int, series: Bool) -> [String] {
        prefs.string("\(prefix):" + (series ? "series:" : "movie:") + String(id))
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func seriesExpected(_ id: Int) -> Set<String> { prefs.stringSet("series_expected:\(id)") }
    static func setSeriesExpected(_ id: Int, _ keys: Set<String>) { prefs.setStringSet("series_expected:\(id)", keys) }
    static func seasonGoal(_ id: Int) -> Int { prefs.int("series_season_goal:\(id)") }
    static func setSeasonGoal(_ id: Int, _ count: Int) {
        if id > 0 && count > 0 { prefs.setInt("series_season_goal:\(id)", count) }
    }
}

/// Punto central de logros (port de AchievementManager). Publica los desbloqueos para el aviso en pantalla.
@MainActor
final class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    @Published var toastQueue: [Achievement] = []
    private var player: AVAudioPlayer?

    private static let groupPlayback = ["first_play", "getting_started", "cinephile", "episode_watcher", "vip", "legend",
                                        "cant_stop", "one_more", "binge", "night_owl", "early_bird", "all_terrain", "no_borders"]
    private static let groupDays = ["veteran", "constant", "streak"]

    func snapshot() -> [Achievement] {
        Achievement.all.map { definition in
            var copy = definition
            copy.progress = progress(definition.id)
            if AchievementStore.isUnlocked(definition.id) {
                copy.unlocked = true
                copy.unlockedAtMs = AchievementStore.unlockedAt(definition.id)
                copy.progress = max(copy.progress, copy.required)
            }
            return copy
        }
    }

    var unlockedCount: Int { AchievementStore.unlockedIds.count }

    func onAppOpened() {
        let today = Clock.dayKey()
        let last = AchievementStore.lastOpenDay
        if today != last {
            let yesterday = Clock.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            let streak = last == yesterday ? AchievementStore.dayStreak + 1 : 1
            AchievementStore.setDayStreak(streak, day: today)
        }
        check(Self.groupDays)
    }

    func onPlaybackStarted(contentId: Int, series: Bool, season: Int, episode: Int) {
        guard contentId > 0 else { return }
        let today = Clock.dayKey()
        if series && season > 0 && episode > 0 {
            let key = AchievementStore.episodeKey(contentId, season, episode)
            AchievementStore.addToSet("played_episodes", key)
            AchievementStore.addToSet("played_contents", key)
            updateEpisodeSequence(contentId, season, episode)
            applyCachedMeta(contentId, series: true)
            AchievementStore.addContentForDay(today, key)
        } else if !series {
            let key = "movie:\(contentId)"
            AchievementStore.addToSet("played_movies", key)
            AchievementStore.addToSet("played_contents", key)
            AchievementStore.setEpisodeStreak(0, key: "")
            applyCachedMeta(contentId, series: false)
            AchievementStore.addContentForDay(today, key)
        } else {
            AchievementStore.setEpisodeStreak(0, key: "")
            applyCachedMeta(contentId, series: true)
        }
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { AchievementStore.setFlag("night_owl") }
        if hour >= 5 && hour < 8 { AchievementStore.setFlag("early_bird") }
        check(Self.groupPlayback)
    }

    func onPlaybackCompleted(contentId: Int, series: Bool, season: Int, episode: Int) {
        guard series, contentId > 0, season > 0, episode > 0 else { return }
        AchievementStore.addToSet("completed_episodes", AchievementStore.episodeKey(contentId, season, episode))
        checkSeriesCompletion(contentId)
        check(["completist"])
    }

    func onSearchSubmitted(_ query: String) {
        AchievementStore.incrementSearch()
        if query.trimmingCharacters(in: .whitespaces).lowercased() == "lzplay" {
            AchievementStore.setFlag("lz_play_found")
            check(["lz_play"])
        }
        check(["explorer"])
    }

    nonisolated func onMyListChanged(count: Int) {
        AchievementStore.setMyListCount(count)
        Task { @MainActor in self.check(["collector", "favorite"]) }
    }

    func cacheContentMeta(contentId: Int, series: Bool, genres: [String], origins: [String]) {
        guard contentId > 0 else { return }
        AchievementStore.cacheMeta(contentId, series: series, genres: genres, origins: origins)
    }

    func setSeriesSeasonGoal(_ id: Int, seasons: Int) { AchievementStore.setSeasonGoal(id, seasons) }

    func registerSeasonEpisodes(_ id: Int, season: Int, numbers: [Int]) {
        guard id > 0, season > 0, !numbers.isEmpty else { return }
        var expected = AchievementStore.seriesExpected(id)
        for number in numbers where number > 0 { expected.insert(AchievementStore.episodeKey(id, season, number)) }
        AchievementStore.setSeriesExpected(id, expected)
        checkSeriesCompletion(id)
        check(["completist"])
    }

    private func applyCachedMeta(_ id: Int, series: Bool) {
        AchievementStore.addAll("genres", AchievementStore.cachedMeta("meta_genres", id, series: series))
        AchievementStore.addAll("origins", AchievementStore.cachedMeta("meta_origins", id, series: series))
    }

    private func updateEpisodeSequence(_ id: Int, _ season: Int, _ episode: Int) {
        let key = "\(id):t\(season):e\(episode)"
        let last = AchievementStore.lastEpisodeKey
        if key == last { return }
        var streak = 1
        if !last.isEmpty && last == "\(id):t\(season):e\(episode - 1)" { streak = AchievementStore.episodeStreak + 1 }
        AchievementStore.setEpisodeStreak(streak, key: key)
    }

    private func checkSeriesCompletion(_ id: Int) {
        let expected = AchievementStore.seriesExpected(id)
        guard !expected.isEmpty, expected.isSubset(of: AchievementStore.set("completed_episodes")) else { return }
        let goal = AchievementStore.seasonGoal(id)
        if goal > 0 {
            let prefix = "episode:\(id):t"
            var seasons = Set<Int>()
            for key in expected where key.hasPrefix(prefix) {
                let rest = key.dropFirst(prefix.count)
                if let mark = rest.range(of: ":e"), let season = Int(rest[..<mark.lowerBound]) { seasons.insert(season) }
            }
            if seasons.count < goal { return }
        }
        AchievementStore.setFlag("series_completed")
    }

    private func progress(_ id: String) -> Int {
        switch id {
        case "first_play", "getting_started", "vip", "legend": return AchievementStore.set("played_contents").count
        case "cinephile": return AchievementStore.set("played_movies").count
        case "episode_watcher": return AchievementStore.set("played_episodes").count
        case "collector", "favorite": return AchievementStore.myListCount
        case "completist": return AchievementStore.flag("series_completed") ? 1 : 0
        case "cant_stop": return AchievementStore.contentsForDay(Clock.dayKey())
        case "one_more", "binge": return AchievementStore.episodeStreak
        case "night_owl": return AchievementStore.flag("night_owl") ? 1 : 0
        case "early_bird": return AchievementStore.flag("early_bird") ? 1 : 0
        case "explorer": return AchievementStore.searchCount
        case "lz_play": return AchievementStore.flag("lz_play_found") ? 1 : 0
        case "veteran": return AchievementStore.set("active_days").count
        case "constant", "streak": return AchievementStore.dayStreak
        case "all_terrain": return AchievementStore.set("genres").count
        case "no_borders": return AchievementStore.set("origins").count
        default: return 0
        }
    }

    private func check(_ ids: [String]) {
        let now = Clock.nowMs
        var newly: [Achievement] = []
        for id in ids {
            guard var achievement = Achievement.all.first(where: { $0.id == id }),
                  !AchievementStore.isUnlocked(id) else { continue }
            achievement.progress = progress(id)
            if achievement.progress >= achievement.required {
                AchievementStore.markUnlocked(id, at: now)
                achievement.unlocked = true
                achievement.unlockedAtMs = now
                newly.append(achievement)
            }
        }
        guard !newly.isEmpty else { return }
        toastQueue.append(contentsOf: newly)
        playUnlockSound()
    }

    func dismissToast() {
        if !toastQueue.isEmpty { toastQueue.removeFirst() }
    }

    private func playUnlockSound() {
        guard let url = Bundle.main.url(forResource: "logro", withExtension: "mp3") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.8
        player?.play()
    }
}
