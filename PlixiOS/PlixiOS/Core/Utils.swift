import Foundation
import Network

enum TextUtil {
    /// Quita acentos y deja minúsculas (equivalente a Normalizer NFD + \p{M}).
    static func stripAccents(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// "Spider-Man: No Way Home" → "spider man no way home".
    static func normalizeSearch(_ value: String) -> String {
        let lowered = stripAccents(value).lowercased().replacingOccurrences(of: "&", with: " ")
        var result = ""
        var lastWasSpace = true
        for scalar in lowered.unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func compactSearch(_ value: String) -> String {
        normalizeSearch(value).replacingOccurrences(of: " ", with: "")
    }

    /// Igual que BackupAccountStore.sanitizeUsername en Android.
    static func sanitizeUsername(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result = ""
        for scalar in lowered.unicodeScalars {
            let allowed = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
                || scalar == "-" || scalar == "_"
            result.append(allowed ? Character(scalar) : "-")
        }
        while result.contains("--") { result = result.replacingOccurrences(of: "--", with: "-") }
        let trimSet = CharacterSet(charactersIn: "-_")
        result = result.trimmingCharacters(in: trimSet)
        if result.count > 60 { result = String(result.prefix(60)) }
        return result
    }

    static func capitalizeFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    static func formatDuration(ms: Int64) -> String {
        let totalSeconds = max(0, ms / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds) }
        return String(format: "%ld:%02ld", minutes, seconds)
    }

    static func formatUsage(ms: Int64) -> String {
        let minutes = ms / 60_000
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return "\(hours) h \(minutes % 60) min"
    }

    static func relativeLastSeen(_ lastSeenMs: Int64, now: Int64 = Clock.nowMs) -> String {
        guard lastSeenMs > 0 else { return "Desconectado" }
        let elapsed = max(0, now - lastSeenMs)
        let minutes = elapsed / 60_000
        if minutes < 1 { return "Hace un momento" }
        if minutes < 60 { return "Hace \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "Hace \(hours) h" }
        let days = hours / 24
        return days == 1 ? "Hace 1 día" : "Hace \(days) días"
    }
}

enum Clock {
    static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func todayISO() -> String { dayKey() }

    static var currentYear: Int { Calendar.current.component(.year, from: Date()) }
}

/// Estado de conexión para mostrar el modo sin conexión.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.isOnline = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "plix.network"))
    }
}
