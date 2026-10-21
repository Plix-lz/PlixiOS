import Foundation

/// Port de StreamUrlUtils.
enum StreamURL {
    static func isHttp(_ url: String?) -> Bool {
        guard let lower = url?.lowercased() else { return false }
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    static func normalize(_ url: String?) -> String {
        guard var value = url?.trimmingCharacters(in: .whitespacesAndNewlines) else { return "" }
        if value.hasPrefix("//") { value = "https:" + value }
        return value.replacingOccurrences(of: "\\/", with: "/")
    }

    static func isPlayableStream(_ raw: String?) -> Bool {
        let url = normalize(raw)
        guard isHttp(url) else { return false }
        let lower = url.lowercased()
        if lower.contains("youtube.com") || lower.contains("youtu.be") || lower.contains("themoviedb.org") { return false }
        let mediaMarkers = [".m3u8", ".mpd", ".mp4", ".m4v", ".mkv", ".webm", "format=m3u8", "type=m3u8", "playlist.m3u"]
        let hasMedia = mediaMarkers.contains { lower.contains($0) }
        if !hasMedia && (lower.contains("/embed/") || lower.contains("/e/") || lower.contains("iframe")) { return false }
        return hasMedia || lower.contains("/hls/") || lower.contains("/hls2/") || lower.contains("/dash/")
    }

    static func isDash(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains(".mpd") || lower.contains("/dash/")
    }

    static func playlistQualityScore(_ url: String) -> Int {
        let lower = url.lowercased()
        var score: Int
        if lower.contains("master") { score = 100 }
        else if lower.contains("playlist") { score = 80 }
        else if lower.contains("index") { score = 70 }
        else if lower.contains("m3u8") { score = 50 }
        else if isDash(lower) { score = 40 }
        else if lower.contains(".mp4") { score = 20 }
        else { score = 0 }
        if lower.contains("/hls/") { score += 8 }
        return score
    }

    static func isJunk(_ url: String) -> Bool {
        let lower = url.lowercased()
        let markers = ["aliexpress", "alicdn", "alibaba", "googletagmanager", "google-analytics", "googleads",
                       "doubleclick", "zoneid=", "request_ab", "betwinner", "amd-cdn-"]
        return markers.contains { lower.contains($0) }
    }

    static func host(_ url: String) -> String {
        URL(string: url)?.host?.lowercased() ?? ""
    }

    static func origin(_ url: String) -> String {
        guard let components = URLComponents(string: url), let scheme = components.scheme, let host = components.host else { return "" }
        if let port = components.port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }
}

/// Port de ServerFamily (detección por dominio).
enum ServerFamily: String {
    case abyss, okru, primeload, nupload, powvideo, streamplay, voe, vidmoly, gscdn, uqload, vimeos,
         lulustream, streamwish, hyper, unknown

    static func from(url raw: String?, label: String? = nil) -> ServerFamily {
        let url = (raw ?? "").lowercased()
        let name = (label ?? "").lowercased()
        if url.contains("abyss") || url.contains("hydrax") || name.contains("abyss") { return .abyss }
        if url.contains("ok.ru") || url.contains("odnoklassniki") || url.contains("okcdn.ru") { return .okru }
        if url.contains("primeload") || url.contains("primecdn") { return .primeload }
        if url.contains("nupload") { return .nupload }
        if isPowVideo(url) || name.contains("powvideo") || name.contains("powcloud") { return .powvideo }
        if isStreamPlay(url) || name.contains("streamplay") { return .streamplay }
        if name.contains("hyper") || url.contains("hyper") { return .hyper }
        if url.contains("voe") || url.contains("cloudwindow") { return .voe }
        if url.contains("vidmoly") { return .vidmoly }
        if url.contains("gscdn") || url.contains("goodstream") { return .gscdn }
        if url.contains("uqload") { return .uqload }
        if url.contains("vimeos") { return .vimeos }
        if url.contains("lulustream") || url.contains("luluvdo") { return .lulustream }
        let wish = ["streamwish", "vidhide", "wishfast", "hgplaycdn", "master.txt", "hglink", "strwish", "embedwish",
                    "flaswish", "hlswish", "streamish", "filelions", "minochinos", "callistanise"]
        if wish.contains(where: { url.contains($0) }) { return .streamwish }
        if name.contains("lulu") { return .lulustream }
        if name.contains("uqload") { return .uqload }
        if name.contains("vidmoly") { return .vidmoly }
        if name.contains("voe") { return .voe }
        if name.contains("vimeos") { return .vimeos }
        return .unknown
    }

    static func isPowVideo(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("powvideo") || lower.contains("powcloud") || lower.contains("powvldeo")
    }

    static func isStreamPlay(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("streamplay") || lower.contains("steamplay") || lower.contains("streamp1ay")
    }

    /// Referer de respaldo por familia (HlsHeaderFactory).
    var fallbackReferer: String? {
        switch self {
        case .vimeos: return "https://vimeos.net/"
        case .gscdn: return "https://gscdn.cam/"
        case .uqload: return "https://uqload.is/"
        default: return nil
        }
    }

    /// Tiempo máximo de captura (ProblemServerPolicy.captureTimeoutMs).
    func captureTimeout(userChoice: Bool, protected: Bool) -> TimeInterval {
        if protected { return userChoice ? 25 : 5 }
        if userChoice {
            switch self {
            case .uqload: return 35
            case .nupload: return 20
            case .okru: return 22
            case .abyss: return 110
            case .voe, .vidmoly, .gscdn, .vimeos, .lulustream, .primeload: return 30
            default: return 25
            }
        }
        switch self {
        case .uqload: return 18
        case .nupload: return 12
        case .okru: return 16
        case .abyss: return 36
        case .lulustream, .voe, .vidmoly, .gscdn, .vimeos, .primeload: return 15
        case .hyper: return 12
        default: return 10
        }
    }
}

/// Port de ServerAutoChain: orden de idioma y de familia para el modal y la cola.
enum ServerChain {
    static let familyPriority = ["direct", "vidhide", "streamwish", "hyper", "voe"]

    static func sortForPlayback(_ servers: [StreamServer]) -> [StreamServer] {
        servers.filter { !$0.url.isEmpty }.enumerated().sorted { lhs, rhs in
            let leftLanguage = languageRank(lhs.element.language)
            let rightLanguage = languageRank(rhs.element.language)
            if leftLanguage != rightLanguage { return leftLanguage < rightLanguage }
            let leftFamily = familyRank(lhs.element)
            let rightFamily = familyRank(rhs.element)
            if leftFamily != rightFamily { return leftFamily < rightFamily }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func languageRank(_ language: String) -> Int {
        let lower = language.lowercased()
        if lower.isEmpty { return 3 }
        if lower.contains("latino") || lower == "lat" || lower == "es-la" { return 0 }
        if lower.contains("castellano") || lower == "es" || lower == "español" || lower == "espanol" { return 1 }
        if lower.contains("inglés") || lower.contains("ingles") || lower.contains("english") || lower.contains("subtitul") || lower == "en" { return 2 }
        return 3
    }

    static func familyRank(_ server: StreamServer) -> Int {
        guard let key = familyKey(server.url, server.name, directStream: server.directStream),
              let index = familyPriority.firstIndex(of: key) else { return familyPriority.count }
        return index
    }

    static func familyKey(_ url: String, _ label: String, directStream: Bool? = nil) -> String? {
        let u = url.lowercased()
        let l = label.lowercased()
        let direct = directStream ?? StreamURL.isPlayableStream(url)
        if direct || [".mp4", ".m3u8", ".mpd", "/hls/", "/hls2/", "/dash/"].contains(where: { u.contains($0) }) { return "direct" }
        if l.contains("hyper") || u.contains("hyper") { return "hyper" }
        if ["vidhide", "minochinos", "filelions", "filemoon"].contains(where: { u.contains($0) })
            || ["vidhide", "filelion", "filemoon"].contains(where: { l.contains($0) }) { return "vidhide" }
        if ["streamwish", "hglink", "strwish", "embedwish", "flaswish", "wishfast", "hgplaycdn", "hlswish", "streamish"].contains(where: { u.contains($0) })
            || l.contains("streamwish") { return "streamwish" }
        if u.contains("voe") || l.contains("voe") || u.contains("cloudwindow") { return "voe" }
        return nil
    }

    /// ProblemServerPolicy.isProtected: servidores cuyo flujo de captura es rápido y estable.
    static func isProtected(_ url: String, _ label: String) -> Bool {
        if StreamURL.isPlayableStream(url) { return true }
        let key = familyKey(url, label)
        if key == "direct" || key == "vidhide" || key == "streamwish" { return true }
        let family = ServerFamily.from(url: url, label: label)
        return family == .powvideo || family == .streamplay
    }

    /// PrimeLoad, Voe y familias con verificación humana necesitan WebView visible.
    static func needsVisibleCapture(_ url: String, _ label: String) -> Bool {
        let family = ServerFamily.from(url: url, label: label)
        return family == .primeload || family == .abyss || family == .voe || family == .powvideo || family == .streamplay
    }
}

enum LanguageGroup: Int, CaseIterable, Identifiable {
    case latino = 0, castellano, subtitulado
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .latino: return "Latino"
        case .castellano: return "Castellano"
        case .subtitulado: return "Subtitulado"
        }
    }

    var flagImage: String {
        switch self {
        case .latino: return "flag_latino.jpg"
        case .castellano: return "flag_castellano.jpg"
        case .subtitulado: return "flag_subtitulado.jpg"
        }
    }

    static func of(_ server: StreamServer) -> LanguageGroup {
        let language = server.language.lowercased()
        if language.contains("castellano") || language.contains("españ") || language.contains("espan") || language == "es" { return .castellano }
        if language.contains("sub") || language.contains("ingl") || language.contains("eng") || language == "en" { return .subtitulado }
        return .latino
    }
}

/// Stream listo para AVPlayer, con las cabeceras que exige el CDN.
struct CapturedStream: Equatable {
    let url: String
    let referer: String
    let embedUrl: String
    var headers: [String: String]
}

/// Port de HlsHeaderFactory.
enum StreamHeaders {
    static let userAgent = HTTP.mobileBrowserUserAgent

    static func build(streamURL: String, referer: String?, embedURL: String?, cookies: String?) -> [String: String] {
        var headers: [String: String] = ["User-Agent": userAgent]
        let family = ServerFamily.from(url: embedURL ?? streamURL)
        var chosenReferer = (referer ?? "").isEmpty ? (embedURL ?? "") : (referer ?? "")
        if chosenReferer.isEmpty || !StreamURL.isHttp(chosenReferer) {
            chosenReferer = family.fallbackReferer ?? ""
        }
        if streamURL.lowercased().contains("rumble") && chosenReferer.isEmpty { chosenReferer = "https://rumble.com/" }
        if !chosenReferer.isEmpty {
            headers["Referer"] = chosenReferer
            let origin = StreamURL.origin(chosenReferer)
            if !origin.isEmpty { headers["Origin"] = origin }
        }
        if let cookies, !cookies.isEmpty { headers["Cookie"] = cookies }
        return headers
    }
}
