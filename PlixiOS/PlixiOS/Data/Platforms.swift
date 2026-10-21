import Foundation

struct PlatformSource: Hashable {
    let path: String
    let query: String
    static func movie(_ query: String) -> PlatformSource { PlatformSource(path: "/discover/movie", query: query) }
    static func tv(_ query: String) -> PlatformSource { PlatformSource(path: "/discover/tv", query: query) }
}

struct PlatformItem: Identifiable, Hashable {
    enum Kind { case streaming, collection }
    let key: String
    let name: String
    let kind: Kind
    let logoUrl: String?
    let embeddedLogo: String?
    let priority: Int
    let tmdbSources: [PlatformSource]
    let githubJsonUrls: [String]
    var id: String { key }
}

/// Reglas de agrupación de PlatformCatalog.
enum PlatformCatalog {
    static let region = "MX"
    static let streamingMaxPriority = 45
    static let listedMaxPriority = 60
    static let excludedProviderIds: Set<Int> = [2, 3, 10]
    private static let variantSuffixes = ["roku premium channel", "apple tv channel", "amazon channel", "standard with ads",
                                          "basic with ads", "with ads", "premium", "plus"]

    private static let aliases: [String: String] = [
        "amazonprimevideo": "primevideo", "amazonprime": "primevideo", "max": "hbomax", "hbo": "hbomax",
        "warnerbros": "hbomax", "warnerbrospictures": "hbomax", "marvel": "disney", "marvelstudios": "disney",
        "pixar": "disney", "fox": "disney", "20thcenturyfox": "disney", "20thcenturystudios": "disney",
        "nationalgeographic": "disney", "star": "disney", "starchannel": "disney", "newlinecinema": "hbomax",
        "dc": "hbomax", "dccomics": "hbomax", "cartoonnetwork": "hbomax", "cartoonnetworks": "hbomax",
        "nickelodeon": "paramount", "mgm": "primevideo", "metrogoldwynmayer": "primevideo",
        "universalpictures": "universal", "dreamworks": "universal", "dreamworksanimation": "universal",
        "sonyone": "sony", "sonypictures": "sony", "sonyanimations": "sony", "sonypicturesanimation": "sony"
    ]

    private static func companies(_ ids: String) -> String {
        "with_companies=" + ids.replacingOccurrences(of: "|", with: "%7C") + "&sort_by=popularity.desc"
    }

    private static func networks(_ ids: String) -> String {
        "with_networks=" + ids.replacingOccurrences(of: "|", with: "%7C") + "&sort_by=popularity.desc"
    }

    static let extraSources: [String: [PlatformSource]] = [
        "disney": [.movie(companies("2|6125|420|13252|3|25|127928|7521|114038")), .tv(companies("420|13252|7521")), .tv(networks("43"))],
        "hbomax": [.movie(companies("174|12|9993|184898|128064|176067|274991")), .tv(networks("49|56")), .tv(companies("9993|184898|128064"))],
        "paramount": [.movie(companies("4|2348")), .tv(networks("13"))],
        "primevideo": [.movie(companies("21"))],
        "universal": [.movie(companies("33|521")), .tv(companies("42141|521"))],
        "sony": [.movie(companies("34|5|2251"))],
        "lionsgate": [.movie(companies("1632"))],
        "lego": [.movie(companies("4081")), .tv(companies("4081"))],
        "animationsadult": [.tv(networks("80"))],
        "hulu": [.tv(networks("453"))],
        "anime": [.tv("with_keywords=210024&with_genres=16&sort_by=popularity.desc"), .movie("with_keywords=210024&with_genres=16&sort_by=popularity.desc")],
        "navidad": [.movie("with_keywords=207317&sort_by=popularity.desc"), .tv("with_keywords=207317&sort_by=popularity.desc")],
        "doramas": [.tv("with_origin_country=KR&with_genres=18&sort_by=popularity.desc")],
        "telenovelas": [.tv("with_genres=10766&with_original_language=es&sort_by=popularity.desc")]
    ]

    static let embeddedLogos: [String: String] = [
        "Animations Adult": "platform_animations_adult.png", "Anime": "platform_anime.jpg", "Apple TV": "platform_apple_tv.png",
        "Cartoon Networks": "platform_cartoon_networks.jpg", "Cine Cristiano": "platform_cine_cristiano.png",
        "DC Comics": "platform_dc_comics.png", "Disney": "platform_disney.jpg", "Doramas": "platform_doramas.png",
        "DreamWorks": "platform_dreamworks.webp", "Fox": "platform_fox.jpg", "HBO Max": "platform_hbo_max.webp",
        "Lego": "platform_lego.png", "LionsGate": "platform_lionsgate.webp", "Lionsgate": "platform_lionsgate.webp",
        "Marvel": "platform_marvel.jpg", "Metro Goldwyn Mayer": "platform_mgm.webp",
        "National Geographic": "platform_national_geographic.jpg", "Navidad": "platform_navidad.jpg",
        "Netflix": "platform_netflix.jpg", "New Line Cinema": "platform_new_line_cinema.png",
        "Nickelodeon": "platform_nickelodeon.jpg", "Paramount": "platform_paramount.jpg", "Pixar": "platform_pixar.png",
        "Prime Video": "platform_prime_video.png", "Sony": "platform_sony.png", "Sony Animations": "platform_sony_animations.png",
        "Star Channel": "platform_star_channel.jpg", "Universal": "platform_universal.jpg", "Vix": "platform_vix.png",
        "Warner Bros": "platform_warner_bros.webp"
    ]

    static func embeddedLogo(for name: String) -> String? {
        if let exact = embeddedLogos[name] { return exact }
        return embeddedLogos.first(where: { $0.key.lowercased() == name.lowercased() })?.value
    }

    static func key(_ name: String) -> String {
        let compact = compactKey(name)
        return aliases[compact] ?? compact
    }

    static func isPrimaryName(_ name: String, key: String) -> Bool { compactKey(name) == key }

    static func compactKey(_ name: String) -> String {
        let base = TextUtil.stripAccents(name).lowercased().replacingOccurrences(of: "+", with: " plus ")
        var text = ""
        var lastSpace = true
        for scalar in base.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                text.unicodeScalars.append(scalar)
                lastSpace = false
            } else if !lastSpace {
                text.append(" ")
                lastSpace = true
            }
        }
        text = text.trimmingCharacters(in: .whitespaces)
        var stripped = true
        while stripped {
            stripped = false
            for suffix in variantSuffixes where text.hasSuffix(" " + suffix) {
                text = String(text.dropLast(suffix.count + 1)).trimmingCharacters(in: .whitespaces)
                stripped = true
            }
        }
        return text.replacingOccurrences(of: " ", with: "")
    }

    static func providerSources(_ ids: [Int]) -> [PlatformSource] {
        guard !ids.isEmpty else { return [] }
        let query = "with_watch_providers=" + ids.map(String.init).joined(separator: "%7C") +
            "&watch_region=\(region)&with_watch_monetization_types=flatrate%7Cfree%7Cads&sort_by=popularity.desc"
        return [.movie(query), .tv(query)]
    }
}

actor PlatformRepository {
    static let shared = PlatformRepository()

    private static let githubListURL = "https://api.github.com/repos/thexxx880/apple/contents/data%20base/plataformas"
    private static let githubRawBase = "https://raw.githubusercontent.com/thexxx880/apple/main/data%20base/plataformas/"
    private static let minContent = 50
    private static let cacheTTL: Int64 = 6 * 60 * 60 * 1000

    private var cached: [PlatformItem]?
    private var cachedAt: Int64 = 0
    private var githubRefsCache: [String: [ContentRef]] = [:]

    private final class Group {
        let key: String
        var providerIds: [Int] = []
        var githubJsonUrls: [String] = []
        var bestPriority = Int.max
        var tmdbName: String?
        var githubName: String?
        var logoUrl: String?
        init(key: String) { self.key = key }
    }

    func loadPlatforms() async throws -> [PlatformItem] {
        if let cached, Clock.nowMs - cachedAt < Self.cacheTTL { return cached }
        var groups: [String: Group] = [:]
        var order: [String] = []
        func group(_ key: String) -> Group {
            if let existing = groups[key] { return existing }
            let created = Group(key: key)
            groups[key] = created
            order.append(key)
            return created
        }

        var tmdbLoaded = false
        let apiKey = AppConfig.tmdbApiKey
        for mediaType in ["movie", "tv"] where !apiKey.isEmpty {
            let address = "\(TMDBClient.apiBase)/watch/providers/\(mediaType)?api_key=\(apiKey)&watch_region=\(PlatformCatalog.region)&language=es-MX"
            guard let response = try? await HTTP.json(address, timeout: 20) else { continue }
            tmdbLoaded = true
            for provider in response.objects("results") {
                let id = provider.int("provider_id")
                let name = provider.str("provider_name").trimmingCharacters(in: .whitespaces)
                guard id > 0, !name.isEmpty, !PlatformCatalog.excludedProviderIds.contains(id) else { continue }
                var priority = provider.int("display_priority", Int.max)
                if let priorities = provider.obj("display_priorities"), priorities[PlatformCatalog.region] != nil {
                    priority = priorities.int(PlatformCatalog.region, priority)
                }
                let key = PlatformCatalog.key(name)
                guard !key.isEmpty else { continue }
                let entry = group(key)
                if !entry.providerIds.contains(id) { entry.providerIds.append(id) }
                if priority < entry.bestPriority {
                    entry.bestPriority = priority
                    entry.tmdbName = name
                    let logo = TMDBClient.text(provider, "logo_path")
                    if !logo.isEmpty { entry.logoUrl = "https://image.tmdb.org/t/p/w154" + logo }
                }
            }
        }

        var githubLoaded = false
        if let data = try? await HTTP.data(Self.githubListURL, timeout: 20),
           let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            githubLoaded = true
            for case let entry as JSONObject in list {
                let fileName = entry.str("name")
                guard fileName.lowercased().hasSuffix(".json") else { continue }
                let name = String(fileName.dropLast(5)).trimmingCharacters(in: .whitespaces)
                let lower = name.lowercased()
                if lower == "otras plataformas" || lower == "sin plataforma" { continue }
                let key = PlatformCatalog.key(name)
                guard !key.isEmpty else { continue }
                let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
                    .replacingOccurrences(of: "+", with: "%2B") ?? fileName
                let entryGroup = group(key)
                entryGroup.githubJsonUrls.append(Self.githubRawBase + encoded)
                if entryGroup.githubName == nil || PlatformCatalog.isPrimaryName(name, key: key) { entryGroup.githubName = name }
            }
        }
        guard tmdbLoaded || githubLoaded else { throw PlixError.message("No se pudieron cargar las plataformas.") }

        var streaming: [PlatformItem] = []
        var collections: [PlatformItem] = []
        for key in order {
            guard let entry = groups[key] else { continue }
            let hasGithub = !entry.githubJsonUrls.isEmpty
            if !hasGithub && entry.bestPriority > PlatformCatalog.listedMaxPriority { continue }
            let sources = PlatformCatalog.providerSources(entry.providerIds) + (PlatformCatalog.extraSources[key] ?? [])
            if sources.isEmpty && !hasGithub { continue }
            let name = entry.githubName ?? entry.tmdbName ?? key
            let kind: PlatformItem.Kind = entry.bestPriority <= PlatformCatalog.streamingMaxPriority ? .streaming : .collection
            let item = PlatformItem(key: key, name: name, kind: kind, logoUrl: entry.logoUrl,
                                    embeddedLogo: entry.githubName.flatMap { PlatformCatalog.embeddedLogo(for: $0) },
                                    priority: entry.bestPriority, tmdbSources: sources, githubJsonUrls: entry.githubJsonUrls)
            if kind == .streaming { streaming.append(item) } else { collections.append(item) }
        }
        streaming.sort { $0.priority != $1.priority ? $0.priority < $1.priority : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        collections.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let all = streaming + collections

        var countFailed = false
        var visible: [PlatformItem] = []
        for platform in all {
            let (keep, failed) = await hasMinimumContent(platform)
            if failed { countFailed = true }
            if keep { visible.append(platform) }
        }
        if tmdbLoaded && githubLoaded && !countFailed {
            cached = visible
            cachedAt = Clock.nowMs
        }
        return visible
    }

    private func hasMinimumContent(_ platform: PlatformItem) async -> (keep: Bool, failed: Bool) {
        var failed = false
        var keys = Set<String>()
        for url in platform.githubJsonUrls {
            if let refs = try? await githubRefs(url) {
                refs.forEach { keys.insert("\($0.type):\($0.id)") }
            } else {
                failed = true
            }
        }
        var count = keys.count
        if count >= Self.minContent { return (true, failed) }
        let apiKey = AppConfig.tmdbApiKey
        for source in platform.tmdbSources {
            let address = "\(TMDBClient.apiBase)\(source.path)?api_key=\(apiKey)&language=es-MX&include_adult=false&page=1&\(source.query)"
            if let response = try? await HTTP.json(address) {
                count += response.int("total_results")
                if count >= Self.minContent { return (true, failed) }
            } else {
                failed = true
            }
        }
        return (failed, failed)
    }

    func githubRefs(_ url: String) async throws -> [ContentRef] {
        if let cachedRefs = githubRefsCache[url] { return cachedRefs }
        let data = try await HTTP.data(url, timeout: 20)
        guard let root = OrderedJSON.parse(data) else { throw PlixError.invalidResponse }
        var refs: [ContentRef] = []
        for (key, value) in root.entries {
            guard let id = Int(key.trimmingCharacters(in: .whitespaces)), id > 0,
                  let link = value.stringValue, !link.isEmpty else { continue }
            refs.append(ContentRef(id: id, type: link.lowercased().contains("contenido-serie") ? ContentType.series : ContentType.movie))
        }
        githubRefsCache[url] = refs
        return refs
    }

    func githubContent(_ urls: [String]) async -> [ContentRef]? {
        guard !urls.isEmpty else { return [] }
        var merged: [ContentRef] = []
        var seen = Set<String>()
        var failures = 0
        for url in urls {
            guard let refs = try? await githubRefs(url) else { failures += 1; continue }
            for ref in refs where !seen.contains("\(ref.type):\(ref.id)") {
                seen.insert("\(ref.type):\(ref.id)")
                merged.append(ref)
            }
        }
        return failures == urls.count ? nil : merged
    }
}

/// Paginación de una plataforma: alterna páginas TMDB con lotes de 18 IDs de GitHub, sin repetir.
@MainActor
final class PlatformContentLoader: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var loading = false
    @Published private(set) var finished = false
    @Published private(set) var failed = false

    private final class SourceState {
        let source: PlatformSource
        var nextPage = 1
        var exhausted = false
        init(_ source: PlatformSource) { self.source = source }
    }

    private let platform: PlatformItem
    private let sources: [SourceState]
    private var seen = Set<String>()
    private var sourceCursor = 0
    private var githubTurn = false
    private var githubRefs: [ContentRef]?
    private var githubIndex = 0
    private var anySuccess = false

    init(platform: PlatformItem) {
        self.platform = platform
        sources = platform.tmdbSources.map(SourceState.init)
    }

    func start() async {
        if platform.githubJsonUrls.isEmpty {
            githubRefs = []
        } else {
            let refs = await PlatformRepository.shared.githubContent(platform.githubJsonUrls)
            if refs != nil { anySuccess = true }
            githubRefs = refs ?? []
        }
        await loadMore()
    }

    private var hasMore: Bool {
        if githubRefs == nil { return true }
        if let githubRefs, githubIndex < githubRefs.count { return true }
        return sources.contains { !$0.exhausted }
    }

    func loadMore() async {
        guard !loading, !finished else { return }
        guard hasMore else { finish(); return }
        loading = true
        defer { loading = false }
        while true {
            let githubPending = (githubRefs?.count ?? 0) > githubIndex
            let tmdbSource = nextSource()
            let useGithub = githubPending && (githubTurn || tmdbSource == nil)
            githubTurn.toggle()
            var batch: [MediaItem] = []
            if useGithub, let refs = githubRefs {
                var chunk: [ContentRef] = []
                while githubIndex < refs.count && chunk.count < 18 {
                    let ref = refs[githubIndex]
                    githubIndex += 1
                    let key = (ref.type == ContentType.series ? "tv" : "movie") + ":\(ref.id)"
                    if !seen.contains(key) { chunk.append(ref) }
                }
                if chunk.isEmpty { continue }
                batch = await TMDBClient.shared.itemsByIds(chunk)
            } else if let source = tmdbSource {
                let page = source.nextPage
                do {
                    let result = try await TMDBClient.shared.discoverPage(path: source.source.path, query: source.source.query, page: page)
                    anySuccess = true
                    source.nextPage = page + 1
                    source.exhausted = source.nextPage > result.totalPages
                    batch = result.items
                } catch {
                    source.exhausted = true
                    continue
                }
            } else {
                finish()
                return
            }
            let fresh = batch.filter { seen.insert($0.key).inserted }
            if !fresh.isEmpty {
                items.append(contentsOf: fresh)
                if !hasMore { finish() }
                return
            }
        }
    }

    private func nextSource() -> SourceState? {
        let count = sources.count
        guard count > 0 else { return nil }
        for offset in 0..<count {
            let index = (sourceCursor + offset) % count
            if !sources[index].exhausted {
                sourceCursor = (index + 1) % count
                return sources[index]
            }
        }
        return nil
    }

    private func finish() {
        finished = true
        failed = !anySuccess && items.isEmpty
    }
}
