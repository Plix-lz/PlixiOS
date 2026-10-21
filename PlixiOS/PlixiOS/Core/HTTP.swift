import Foundation

enum HTTP {
    static let appUserAgent = "PLIX-iOS"
    static let mobileBrowserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024)
        return URLSession(configuration: configuration)
    }()

    static func data(
        _ urlString: String,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15,
        userAgent: String = appUserAgent
    ) async throws -> Data {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw PlixError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw PlixError.http(http.statusCode)
        }
        return data
    }

    static func json(_ urlString: String, headers: [String: String] = [:], timeout: TimeInterval = 15,
                     userAgent: String = appUserAgent) async throws -> JSONObject {
        try JSONUtil.object(from: try await data(urlString, headers: headers, timeout: timeout, userAgent: userAgent))
    }

    static func text(_ urlString: String, headers: [String: String] = [:], timeout: TimeInterval = 15,
                     userAgent: String = appUserAgent) async throws -> String {
        let body = try await data(urlString, headers: headers, timeout: timeout, userAgent: userAgent)
        return String(decoding: body, as: UTF8.self)
    }

    /// Comprueba si existe un archivo remoto sin descargarlo completo.
    static func exists(_ urlString: String, timeout: TimeInterval = 8) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        request.setValue(appUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum AppConfig {
    static var tmdbApiKey: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "TMDBApiKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}
