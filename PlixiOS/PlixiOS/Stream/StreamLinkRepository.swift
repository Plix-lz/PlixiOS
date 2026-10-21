import Foundation

/// Port de StreamLinkRepository: reúne enlaces de GitHub, embed-final, Embed69, CuevanaCZ y HLS/4.
/// Todas las APIs PHP son remotas (pelixplay.app); el iPhone solo consume su JSON por HTTPS.
actor StreamLinkRepository {
    static let shared = StreamLinkRepository()

    private static let listMovieJSON = "https://raw.githubusercontent.com/thexxx880/API/main/content/API/JSON/list-movie.JSON"
    private static let appleMovieBase = "https://raw.githubusercontent.com/thexxx880/apple/main/data%20base/data/movie/"
    private static let serieBase = "https://raw.githubusercontent.com/thexxx880/apple/main/data%20base/data/serie/"
    private static let embed69API = "https://pelixplay.app/apis/embed69/worker_final.php?id="
    private static let cuevanaAPI = "https://pelixplay.app/apis/cuevanacz/extract.php?id="
    private static let hls4API = "https://pelixplay.app/apis/hls/4/api.php?action=details&id="
    private static let embedFinalAPI = "https://pelixplay.app/embed/api.php?action=details&id="
    private static let embedFinalCacheMs: Int64 = 3 * 60 * 1000
    private static let userAgent = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"

    private static let embedFinalNames: [String: String] = [
        "streamwish": "StreamWish", "vidmoly": "Vidmoly", "voe": "VOE", "uqload": "UQload", "vidspeed": "VidSpeed",
        "filelions": "FileLions - VidHide", "vidhide": "VidHide", "doodstream": "DoodStream", "primeload": "PrimeLoad",
        "vimeos": "Vimeos", "powvideo": "PowVideo", "powcloud": "Powcloud", "streamplay": "Streamplay",
        "streamhide": "StreamHide", "mp4upload": "Mp4Upload", "hxfile": "HXFile"
    ]
    private static let languageMarkers: [(String, String)] = [
        ("subtitulado", "Inglés"), ("castellano", "Castellano"), ("espanol", "Castellano"),
        ("ingles", "Inglés"), ("engsub", "Inglés")
    ]

    private var embedFinalCache: [String: (servers: [StreamServer], loadedAt: Int64)] = [:]
    private var seriesLanguage: [String: String] = [:]
    private var listMovieCache: (json: OrderedJSON, loadedAt: Int64)?

    /// Lista progresiva: `onUpdate` recibe la lista acumulada; la última llamada trae `complete = true`.
    func fetchProgressive(contentId: Int, isSeries: Bool, season: Int, episode: Int,
                          onUpdate: @escaping @MainActor ([StreamServer], Bool) -> Void) async {
        let id = String(contentId)
        var all: [StreamServer] = []
        var seen = Set<String>()
        let apiSeason = isSeries ? season : -1
        let apiEpisode = isSeries ? episode : -1

        func publish(_ complete: Bool) async {
            let snapshot = all
            await onUpdate(snapshot, complete)
        }

        if isSeries && season > 0 && episode > 0 {
            all += await fetchEpisodeGithub(id, season: season, episode: episode, seen: &seen)
        } else {
            all += await fetchMovieGithub(id, seen: &seen)
            all += await fetchMovieApple(id, seen: &seen)
        }
        await publish(false)
        if Task.isCancelled { return }

        for server in await embedFinalServers(contentId: id, season: apiSeason, episode: apiEpisode) {
            Self.addServer(&all, &seen, url: server.url, label: server.name, language: server.language)
        }
        await publish(false)
        if Task.isCancelled { return }

        all += await fetchLanguageGroupsAPI(Self.embed69API, id: id, season: apiSeason, episode: apiEpisode,
                                            seasonOnlyWithEpisode: true, timeout: 10, seen: &seen)
        await publish(false)
        if Task.isCancelled { return }

        all += await fetchLanguageGroupsAPI(Self.cuevanaAPI, id: id, season: apiSeason, episode: apiEpisode,
                                            seasonOnlyWithEpisode: false, timeout: 8, seen: &seen)
        await publish(false)
        if Task.isCancelled { return }

        all += await fetchAllEmbedsAPI(Self.hls4API, id: id, season: apiSeason, episode: apiEpisode,
                                       seen: &seen, prettyLabels: false)
        await publish(true)
    }

    private func get(_ url: String, timeout: TimeInterval) async -> Data? {
        try? await HTTP.data(url, headers: ["Accept": "application/json,*/*"], timeout: timeout, userAgent: Self.userAgent)
    }

    private func fetchMovieGithub(_ id: String, seen: inout Set<String>) async -> [StreamServer] {
        var out: [StreamServer] = []
        let root: OrderedJSON
        if let cache = listMovieCache, Clock.nowMs - cache.loadedAt < 10 * 60 * 1000 {
            root = cache.json
        } else {
            guard let data = await get(Self.listMovieJSON, timeout: 8), let parsed = OrderedJSON.parse(data) else { return out }
            listMovieCache = (parsed, Clock.nowMs)
            root = parsed
        }
        guard let entry = root[id], entry.isObject else { return out }
        if let links = entry["enlaces"], links.isArray {
            Self.addFromArray(&out, &seen, links, language: "Latino")
        } else if let links = entry["enlace"], links.isArray {
            Self.addFromArray(&out, &seen, links, language: "Latino")
        } else {
            var url = entry.string("enlace")
            if url.isEmpty { url = entry.string("enlaces") }
            Self.addServer(&out, &seen, url: url, label: Self.nameFromURL(url), language: "Latino")
        }
        return out
    }

    private func fetchMovieApple(_ id: String, seen: inout Set<String>) async -> [StreamServer] {
        var out: [StreamServer] = []
        guard let data = await get(Self.appleMovieBase + id + "/" + id + ".json", timeout: 8),
              let json = OrderedJSON.parse(data) else { return out }
        let video = json.string("enlace_video")
        Self.addServer(&out, &seen, url: video, label: Self.nameFromURL(video), language: "Latino")
        return out
    }

    private func fetchEpisodeGithub(_ id: String, season: Int, episode: Int, seen: inout Set<String>) async -> [StreamServer] {
        var out: [StreamServer] = []
        let language = await resolveSeriesLanguage(id)
        guard let data = await get(Self.serieBase + id + "/t\(season)/" + id + ".json", timeout: 8),
              let json = OrderedJSON.parse(data) else { return out }
        let episodes = (json["capitulos"]?.isObject ?? false) ? json["capitulos"]! : json
        let key = String(episode)
        if let links = episodes[key], links.isArray {
            Self.addFromArray(&out, &seen, links, language: language)
        } else {
            let url = episodes.string(key)
            Self.addServer(&out, &seen, url: url, label: Self.nameFromURL(url), language: language)
        }
        return out
    }

    /// Un JSON vacío en la raíz de la serie marca su idioma (p. ej. `subtitulado.json`). Sin marcador: Latino.
    private func resolveSeriesLanguage(_ id: String) async -> String {
        if let cached = seriesLanguage[id] { return cached }
        var language = "Latino"
        for (marker, label) in Self.languageMarkers {
            if await get(Self.serieBase + id + "/" + marker + ".json", timeout: 4) != nil {
                language = label
                break
            }
        }
        seriesLanguage[id] = language
        return language
    }

    private func fetchLanguageGroupsAPI(_ base: String, id: String, season: Int, episode: Int,
                                        seasonOnlyWithEpisode: Bool, timeout: TimeInterval,
                                        seen: inout Set<String>) async -> [StreamServer] {
        var out: [StreamServer] = []
        var api = base + id
        if seasonOnlyWithEpisode {
            if season > 0 && episode > 0 { api += "&season=\(season)&episode=\(episode)" }
        } else {
            if season > 0 { api += "&season=\(season)" }
            if episode > 0 { api += "&episode=\(episode)" }
        }
        guard let data = await get(api, timeout: timeout), let json = OrderedJSON.parse(data),
              json["error"] == nil, let embeds = json["embeds"], embeds.isObject else { return out }
        for groupKey in Self.orderedLanguageKeys(embeds) {
            guard let group = embeds[groupKey], group.isObject else { continue }
            let language = Self.languageForGroupKey(groupKey)
            for (server, value) in group.entries {
                let url = (value.stringValue ?? "").trimmingCharacters(in: .whitespaces)
                guard !url.isEmpty else { continue }
                let label = server.isEmpty ? Self.nameFromURL(url) : TextUtil.capitalizeFirst(server)
                Self.addServer(&out, &seen, url: url, label: label, language: language)
            }
        }
        return out
    }

    /// Servidores del embed-final, con caché de 3 minutos compartida con la búsqueda de HLS directo.
    func embedFinalServers(contentId: String, season: Int, episode: Int) async -> [StreamServer] {
        let tv = season > 0 && episode > 0
        let key = tv ? "\(contentId):\(season):\(episode)" : contentId
        if let cached = embedFinalCache[key], Clock.nowMs - cached.loadedAt < Self.embedFinalCacheMs {
            return cached.servers
        }
        var seen = Set<String>()
        let servers = await fetchAllEmbedsAPI(Self.embedFinalAPI, id: contentId, season: tv ? season : -1,
                                              episode: tv ? episode : -1, seen: &seen, prettyLabels: true)
        if !servers.isEmpty { embedFinalCache[key] = (servers, Clock.nowMs) }
        return servers
    }

    private func fetchAllEmbedsAPI(_ base: String, id: String, season: Int, episode: Int,
                                   seen: inout Set<String>, prettyLabels: Bool) async -> [StreamServer] {
        var out: [StreamServer] = []
        let tv = season > 0 && episode > 0
        var api = base + id + "&type=" + (tv ? "tv" : "movie")
        if tv { api += "&season=\(season)&episode=\(episode)" }
        guard let data = await get(api, timeout: 10), let json = OrderedJSON.parse(data), json.bool("ok") else { return out }
        var allEmbeds: OrderedJSON
        if let embedsAll = json["all_embeds"], embedsAll.isObject {
            allEmbeds = embedsAll
        } else if let embeds = json["embeds"], embeds.isObject {
            let language = json.string("language").isEmpty ? "latino" : json.string("language")
            allEmbeds = .object([(language, embeds)])
        } else {
            return out
        }
        for groupKey in Self.orderedLanguageKeys(allEmbeds) {
            guard let group = allEmbeds[groupKey], group.isObject else { continue }
            let language = Self.languageForGroupKey(groupKey)
            for (server, value) in group.entries {
                var urls: [String] = []
                if value.isArray {
                    urls = value.items.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                } else if case .string(let text) = value {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { urls = [trimmed] }
                }
                for (index, url) in urls.enumerated() {
                    var base = prettyLabels ? Self.prettyServerKey(server) : TextUtil.capitalizeFirst(server)
                    if base.isEmpty { base = Self.nameFromURL(url) }
                    Self.addServer(&out, &seen, url: url, label: index == 0 ? base : "\(base) (\(index + 1))", language: language)
                }
            }
        }
        return out
    }

    // MARK: Utilidades estáticas

    static func orderedLanguageKeys(_ groups: OrderedJSON) -> [String] {
        var latino: [String] = []
        var castellano: [String] = []
        var subtitulado: [String] = []
        for (key, _) in groups.entries {
            switch languageForGroupKey(key) {
            case "Castellano": castellano.append(key)
            case "Inglés": subtitulado.append(key)
            default: latino.append(key)
            }
        }
        return latino + castellano + subtitulado
    }

    static func languageForGroupKey(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespaces).lowercased()
        if k.contains("castellano") || k.contains("espanol") || k.contains("español") || k == "es" || k == "spain" { return "Castellano" }
        if k.contains("sub") || k.contains("ingl") || k.contains("eng") || k.contains("vose") || k == "en" { return "Inglés" }
        return "Latino"
    }

    /// `filelions` → "FileLions - VidHide", `voe_2` → "VOE 2", `servidorgoldmember` → "Goldmember".
    static func prettyServerKey(_ key: String) -> String {
        var value = key.trimmingCharacters(in: .whitespaces).lowercased()
        if value.isEmpty { return key }
        if value.hasPrefix("servidor") && value.count > "servidor".count { value = String(value.dropFirst("servidor".count)) }
        var base = value
        var number = ""
        if let regex = try? NSRegularExpression(pattern: "^(.*?)[_-]?(\\d+)$"),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let baseRange = Range(match.range(at: 1), in: value), let numberRange = Range(match.range(at: 2), in: value),
           !value[baseRange].isEmpty {
            base = String(value[baseRange])
            number = String(value[numberRange])
        }
        base = base.filter { ($0.isLetter && $0.isASCII) || ($0.isNumber && $0.isASCII) }
        let name = embedFinalNames[base] ?? TextUtil.capitalizeFirst(base.isEmpty ? value : base)
        return number.isEmpty ? name : "\(name) \(number)"
    }

    static func addFromArray(_ dest: inout [StreamServer], _ seen: inout Set<String>, _ array: OrderedJSON, language: String) {
        for item in array.items {
            if item.isObject {
                var url = item.string("url")
                if url.isEmpty { url = item.string("video") }
                url = url.trimmingCharacters(in: .whitespaces)
                let label = item.string("label").isEmpty ? nameFromURL(url) : item.string("label")
                addServer(&dest, &seen, url: url, label: label, language: language)
            } else {
                let url = (item.stringValue ?? "").trimmingCharacters(in: .whitespaces)
                addServer(&dest, &seen, url: url, label: nameFromURL(url), language: language)
            }
        }
    }

    static func addServer(_ dest: inout [StreamServer], _ seen: inout Set<String>, url: String, label: String, language: String) {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, StreamURL.isHttp(StreamURL.normalize(clean)), !isBlocked(clean, label) else { return }
        let key = clean.lowercased()
        guard !seen.contains(key) else { return }
        seen.insert(key)
        dest.append(StreamServer(name: label.isEmpty ? nameFromURL(clean) : label, url: clean,
                                 directStream: StreamURL.isPlayableStream(clean), language: language))
    }

    /// Doodstream y Playmogo no entregan HLS reproducible; Filemoon está oculto.
    static func isBlocked(_ url: String, _ label: String) -> Bool {
        let u = url.lowercased()
        let l = label.lowercased()
        if l.contains("dood") || l.contains("filemoon") { return true }
        return ["doodstream", "dood.", "doodcdn", "doimg.net", "playmogo", "filemoon", "kerapoxy", "moonmov"].contains { u.contains($0) }
    }

    static func nameFromURL(_ url: String) -> String {
        if url.isEmpty { return "Externo" }
        let lower = url.lowercased()
        if lower.contains(".mp4") || lower.contains(".m3u8") { return "Directo" }
        if lower.contains("vidhide") || lower.contains("minochinos") { return "VidHide" }
        if lower.contains("filelions") || lower.contains("filemoon") { return "FileLions" }
        if lower.contains("hyper") { return "Hyper" }
        if lower.contains("streamwish") { return "StreamWish" }
        if lower.contains("voe") { return "Voe" }
        if lower.contains("uqload") { return "Uqload" }
        if lower.contains("lulustream") { return "LuluStream" }
        if ServerFamily.isStreamPlay(url) { return "Streamplay" }
        if ServerFamily.isPowVideo(url) { return "PowVideo" }
        if lower.contains("vidmoly") { return "Vidmoly" }
        if lower.contains("gscdn") { return "GsCDN" }
        if lower.contains("goodstream") { return "GoodStream" }
        if lower.contains("vimeos") { return "Vimeos" }
        if lower.contains("nupload") { return "Nupload" }
        if lower.contains("primeload") || lower.contains("primecdn") { return "PrimeLoad" }
        if lower.contains("ok.ru") || lower.contains("odnoklassniki") || lower.contains("okcdn.ru") { return "OK.ru" }
        if lower.contains("abyss") || lower.contains("abysscdn") || lower.contains("hydrax") { return "abyss.to" }
        var host = StreamURL.host(url).replacingOccurrences(of: "www.", with: "")
        if let dot = host.firstIndex(of: ".") { host = String(host[..<dot]) }
        return host.isEmpty ? "Externo" : TextUtil.capitalizeFirst(host)
    }
}

/// Port de PelixplayHlsResolver: pide al extractor remoto un HLS sin token para reproducir directo.
enum PelixplayHLSResolver {
    private static let extractURL = "https://pelixplay.app/embed/extract.php"
    private static let embedReferer = "https://pelixplay.app/embed/embed-final.html"
    private static let maxAttempts = 6
    private static let totalBudget: TimeInterval = 25

    static func resolve(contentId: Int, season: Int, episode: Int) async -> (StreamServer, CapturedStream)? {
        let deadline = Date().addingTimeInterval(totalBudget)
        let servers = await StreamLinkRepository.shared.embedFinalServers(contentId: String(contentId), season: season, episode: episode)
        var attempts = 0
        for server in servers {
            if Task.isCancelled || attempts >= maxAttempts || Date() >= deadline { break }
            guard isExtractable(server) else { continue }
            attempts += 1
            if let stream = await extract(server.url) { return (server, stream) }
        }
        return nil
    }

    static func isExtractable(_ server: StreamServer) -> Bool {
        let family = ServerChain.familyKey(server.url, server.name)
        if family == "streamwish" || family == "vidhide" { return true }
        let u = server.url.lowercased()
        let l = server.name.lowercased()
        return u.contains("uqload") || l.contains("uqload") || u.contains("vidspeed") || l.contains("vidspeed")
    }

    static func extract(_ embedURL: String) async -> CapturedStream? {
        guard let url = URL(string: extractURL) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json,*/*", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(embedReferer, forHTTPHeaderField: "Referer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": normalizeForExtractor(embedURL)])
        guard let (data, response) = try? await HTTP.session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONUtil.object(from: data), json["error"] == nil else { return nil }
        let streams = (json["streams"] as? [Any])?.map { ($0 as? String) ?? "" } ?? []
        guard !streams.isEmpty else { return nil }
        let labels = (json["labels"] as? [Any])?.map { ($0 as? String) ?? "" } ?? []
        let meta = (json["meta"] as? [Any])?.map { ($0 as? JSONObject) ?? [:] } ?? []
        var chosen = -1
        for (index, label) in labels.enumerated() where index < streams.count {
            let hasToken = index < meta.count && meta[index].bool("has_token")
            if label.lowercased() == "hls3" && !hasToken { chosen = index; break }
        }
        if chosen < 0 {
            for (index, entry) in meta.enumerated() where index < streams.count {
                if entry["has_token"] != nil && !entry.bool("has_token", true) && entry.bool("is_m3u8") { chosen = index; break }
            }
        }
        guard chosen >= 0, StreamURL.isHttp(streams[chosen]) else { return nil }
        var referer = json.str("referer")
        if !StreamURL.isHttp(referer) { referer = embedURL }
        let hls = streams[chosen]
        return CapturedStream(url: hls, referer: referer, embedUrl: embedURL,
                              headers: StreamHeaders.build(streamURL: hls, referer: referer, embedURL: embedURL, cookies: nil))
    }

    /// extract.php espera /v/{code} para los mirrors de VidHide/FileLions.
    static func normalizeForExtractor(_ url: String) -> String {
        let lower = url.lowercased()
        guard ["filelions", "vidhide", "minochinos", "callistanise"].contains(where: { lower.contains($0) }),
              let path = URL(string: url)?.path else { return url }
        for segment in path.split(separator: "/").reversed() {
            var cleaned = String(segment)
            for suffix in [".html", ".htm", ".php"] where cleaned.lowercased().hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
            let valid = cleaned.count >= 4 && cleaned.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "-" }
            if valid { return "https://callistanise.com/v/" + cleaned }
        }
        return url
    }
}
