import Foundation

/// Valor tipado equivalente a los tipos de SharedPreferences de Android.
/// El formato en disco y en la nube es el mismo que usa Android (`{"t":"s|i|l|b|f|ss","v":...}`),
/// así un respaldo creado en Android se puede restaurar en iOS y viceversa.
enum PrefValue: Equatable {
    case string(String)
    case int(Int)
    case long(Int64)
    case bool(Bool)
    case float(Double)
    case stringSet(Set<String>)

    var typed: JSONObject {
        switch self {
        case .string(let value): return ["t": "s", "v": value]
        case .int(let value): return ["t": "i", "v": value]
        case .long(let value): return ["t": "l", "v": value]
        case .bool(let value): return ["t": "b", "v": value]
        case .float(let value): return ["t": "f", "v": value]
        case .stringSet(let value): return ["t": "ss", "v": Array(value).sorted()]
        }
    }

    init?(typed: JSONObject) {
        let type = typed.str("t")
        switch type {
        case "s": self = .string(typed.str("v"))
        case "i": self = .int(typed.int("v"))
        case "l": self = .long(typed.int64("v"))
        case "b": self = .bool(typed.bool("v"))
        case "f": self = .float(typed.double("v"))
        case "ss":
            let values = (typed["v"] as? [Any])?.compactMap { $0 as? String } ?? []
            self = .stringSet(Set(values))
        default: return nil
        }
    }
}

extension Notification.Name {
    static let plixPrefsChanged = Notification.Name("plix.prefs.changed")
}

/// Archivo de preferencias con nombre, persistido como JSON en Application Support.
final class Prefs {
    let name: String
    private let fileURL: URL
    private let lock = NSLock()
    private var values: [String: PrefValue]

    fileprivate init(name: String, directory: URL) {
        self.name = name
        fileURL = directory.appendingPathComponent(Prefs.fileName(for: name))
        values = Prefs.load(from: fileURL)
    }

    static func fileName(for name: String) -> String {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" }
        return String(safe) + ".json"
    }

    private static func load(from url: URL) -> [String: PrefValue] {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject else { return [:] }
        var result: [String: PrefValue] = [:]
        for (key, raw) in root {
            if let typed = raw as? JSONObject, let value = PrefValue(typed: typed) { result[key] = value }
        }
        return result
    }

    // MARK: Lectura

    func string(_ key: String, _ fallback: String = "") -> String {
        lock.lock(); defer { lock.unlock() }
        if case .string(let value)? = values[key] { return value }
        return fallback
    }

    func optionalString(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if case .string(let value)? = values[key] { return value }
        return nil
    }

    func int(_ key: String, _ fallback: Int = 0) -> Int {
        lock.lock(); defer { lock.unlock() }
        switch values[key] {
        case .int(let value)?: return value
        case .long(let value)?: return Int(value)
        default: return fallback
        }
    }

    func long(_ key: String, _ fallback: Int64 = 0) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        switch values[key] {
        case .long(let value)?: return value
        case .int(let value)?: return Int64(value)
        default: return fallback
        }
    }

    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if case .bool(let value)? = values[key] { return value }
        return fallback
    }

    func float(_ key: String, _ fallback: Double = 0) -> Double {
        lock.lock(); defer { lock.unlock() }
        if case .float(let value)? = values[key] { return value }
        return fallback
    }

    func stringSet(_ key: String) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        if case .stringSet(let value)? = values[key] { return value }
        return []
    }

    func contains(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return values[key] != nil
    }

    var keys: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(values.keys)
    }

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return values.isEmpty
    }

    func snapshot() -> [String: PrefValue] {
        lock.lock(); defer { lock.unlock() }
        return values
    }

    // MARK: Escritura

    func set(_ key: String, _ value: PrefValue?) {
        edit { $0[key] = value }
    }

    func setString(_ key: String, _ value: String) { set(key, .string(value)) }
    func setInt(_ key: String, _ value: Int) { set(key, .int(value)) }
    func setLong(_ key: String, _ value: Int64) { set(key, .long(value)) }
    func setBool(_ key: String, _ value: Bool) { set(key, .bool(value)) }
    func setFloat(_ key: String, _ value: Double) { set(key, .float(value)) }
    func setStringSet(_ key: String, _ value: Set<String>) { set(key, .stringSet(value)) }
    func remove(_ key: String) { set(key, nil) }

    func clear() {
        edit { $0.removeAll() }
    }

    /// Aplica varios cambios y guarda una sola vez.
    func edit(notify: Bool = true, _ changes: (inout [String: PrefValue]) -> Void) {
        lock.lock()
        let before = values
        changes(&values)
        let changed = before != values
        let copy = values
        lock.unlock()
        guard changed else { return }
        persist(copy)
        guard notify else { return }
        PrefsRegistry.shared.didChange(name: name)
    }

    func replaceAll(with newValues: [String: PrefValue]) {
        edit { $0 = newValues }
    }

    private func persist(_ snapshot: [String: PrefValue]) {
        var root: JSONObject = [:]
        for (key, value) in snapshot { root[key] = value.typed }
        guard let data = try? JSONSerialization.data(withJSONObject: root) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Exporta en el formato de LocalPrefsBackup de Android.
    func exportPayload() -> String {
        var root: JSONObject = [:]
        for (key, value) in snapshot() { root[key] = value.typed }
        return JSONUtil.string(root)
    }

    func importPayload(_ payload: String) {
        guard let root = JSONUtil.object(from: payload) else { return }
        var result: [String: PrefValue] = [:]
        for (key, raw) in root {
            if let typed = raw as? JSONObject, let value = PrefValue(typed: typed) { result[key] = value }
        }
        edit(notify: false) { $0 = result }
        NotificationCenter.default.post(name: .plixPrefsChanged, object: name)
    }
}

final class PrefsRegistry {
    static let shared = PrefsRegistry()

    let directory: URL
    private var cache: [String: Prefs] = [:]
    private let lock = NSLock()

    /// Se llama cuando cambian datos que forman parte del respaldo en la nube.
    var onBackedUpDataChanged: ((String) -> Void)?

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("prefs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func prefs(_ name: String) -> Prefs {
        lock.lock(); defer { lock.unlock() }
        if let existing = cache[name] { return existing }
        let created = Prefs(name: name, directory: directory)
        cache[name] = created
        return created
    }

    /// Nombres de todos los archivos de preferencias existentes en disco o abiertos en memoria.
    func allNames() -> [String] {
        var names = Set<String>()
        lock.lock()
        names.formUnion(cache.keys)
        lock.unlock()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".json") {
            names.insert(String(file.dropLast(5)))
        }
        return names.sorted()
    }

    fileprivate func didChange(name: String) {
        NotificationCenter.default.post(name: .plixPrefsChanged, object: name)
        if BackupPolicy.shouldBackup(name) {
            onBackedUpDataChanged?(name)
        }
    }
}

enum BackupPolicy {
    /// Mismas reglas que BackupAccountStore en Android: todo `plix_*` salvo sesión, credenciales y cachés.
    static func shouldBackup(_ name: String) -> Bool {
        guard name.hasPrefix("plix_") else { return false }
        if name.hasPrefix("plix_firestore") || name.hasPrefix("plix_github") { return false }
        if name == "plix_account_pin" || name.hasPrefix("plix_cache_") { return false }
        if name == "plix_profile_avatar_catalog_cache" || name == "plix_profile_backdrop_catalog_cache" { return false }
        return true
    }

    /// Siempre se suben aunque estén vacías (igual que KNOWN_PREFS en Android).
    static let knownPrefs = ["plix_my_list", "plix_content_history", "plix_playback_progress", "plix_achievements",
                             "plix_genre_taste", "plix_header_logo", "plix_app_usage", "plix_profile_avatar",
                             "plix_profile_backdrop"]

    static func discoverNames() -> [String] {
        var names = knownPrefs
        for name in PrefsRegistry.shared.allNames() where shouldBackup(name) && !names.contains(name) {
            names.append(name)
        }
        return names
    }
}
