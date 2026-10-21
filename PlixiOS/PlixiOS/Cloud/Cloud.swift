import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Firebase solo se inicializa si `GoogleService-Info.plist` está en el bundle.
/// Sin ese archivo la app funciona completa en modo local (sin cuenta, amigos ni Cine Virtual).
enum CloudConfig {
    private(set) static var isConfigured = false

    static func configureIfPossible() {
        guard !isConfigured,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        isConfigured = true
    }

    static var db: Firestore? { isConfigured ? Firestore.firestore() : nil }
    static var auth: Auth? { isConfigured ? Auth.auth() : nil }
    static var currentUid: String? { auth?.currentUser?.uid }

    static func requireDB() throws -> Firestore {
        guard let db else { throw PlixError.firebaseUnavailable }
        return db
    }
}

/// Mismas colecciones y formatos que FirestoreSyncConfig (Android).
enum SyncConfig {
    static let users = "users"
    static let accounts = "accounts"
    static let prefs = "prefs"
    static let metadata = "metadata"
    static let meta = "meta"
    static let plixUserIdsDoc = "plixUserIds"
    static let publicProfiles = "publicProfiles"
    static let plixUserIdIndex = "plixUserIdIndex"
    static let friendRequests = "friendRequests"
    static let friends = "friends"
    static let presence = "presence"
    static let syncDoc = "sync"
    static let emailDomain = "@plix2.app"
    static let passwordPrefix = "plix:"
    static let presenceOnlineMs: Int64 = 90_000
    static let sessionPrefs = "plix_firestore_sync"

    static func email(_ username: String) -> String { TextUtil.sanitizeUsername(username) + emailDomain }
    static func password(_ pin: String) -> String { passwordPrefix + pin }

    static func formatPlixUserId(_ id: Int64) -> String {
        id <= 0 ? "" : String(format: "#%08lld", id)
    }

    static func parsePlixUserId(_ raw: String) -> Int64 {
        var cleaned = raw.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        return Int64(cleaned) ?? 0
    }
}

enum FirestoreValue {
    static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let text = value as? String { return text.trimmingCharacters(in: .whitespaces) }
        return "\(value)".trimmingCharacters(in: .whitespaces)
    }

    static func long(_ value: Any?, _ fallback: Int64 = 0) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String, let parsed = Int64(text.trimmingCharacters(in: .whitespaces)) { return parsed }
        return fallback
    }

    static func bool(_ value: Any?, _ fallback: Bool = false) -> Bool {
        (value as? Bool) ?? fallback
    }

    static func double(_ value: Any?, _ fallback: Double) -> Double {
        (value as? NSNumber)?.doubleValue ?? fallback
    }

    static func avatar(_ raw: Any?, requireAll: Bool = true) -> AvatarRef? {
        guard let map = raw as? [String: Any] else { return nil }
        let folder = string(map["folder"])
        let pack = string(map["pack"])
        let id = string(map["id"])
        if id.isEmpty || (requireAll && (folder.isEmpty || pack.isEmpty)) { return nil }
        return AvatarRef(folder: folder, pack: pack, id: id, ext: string(map["extension"]))
    }

    static func avatarMap(_ ref: AvatarRef) -> [String: Any] {
        var map: [String: Any] = ["folder": ref.folder, "pack": ref.pack, "id": ref.id]
        if !ref.ext.isEmpty { map["extension"] = ref.ext }
        return map
    }
}

/// Mensajes de error iguales a los de Android.
enum CloudError {
    static let authDomain = "FIRAuthErrorDomain"
    static let emailAlreadyInUse = 17007
    static let wrongPassword = 17009
    static let invalidCredential = 17004
    static let userMismatch = 17024
    static let networkError = 17020
    static let tooManyRequests = 17010
    static let operationNotAllowed = 17006

    static func authCode(_ error: Error) -> Int? {
        let nsError = error as NSError
        return nsError.domain == authDomain ? nsError.code : nil
    }

    static func map(_ error: Error) -> PlixError {
        if let plix = error as? PlixError { return plix }
        if authCode(error) == operationNotAllowed {
            return .message("Activa Email/Password en Firebase Authentication.")
        }
        return .message("No se pudo conectar con Firebase.\nInténtalo nuevamente.")
    }
}
