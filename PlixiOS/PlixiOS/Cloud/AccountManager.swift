import FirebaseAuth
import FirebaseFirestore
import Foundation
import UserNotifications

/// Estado de la sesión de respaldo (equivalente a BackupAccountStore). No se sube a la nube.
enum SessionStore {
    private static var prefs: Prefs { PrefsRegistry.shared.prefs(SyncConfig.sessionPrefs) }

    static var isSignedIn: Bool { prefs.bool("signed_in") && !uid.isEmpty }
    static var uid: String { prefs.string("uid") }
    static var username: String { prefs.string("username") }
    static var plixUserId: Int64 { prefs.long("plix_user_id") }
    static var lastBackupMs: Int64 { prefs.long("last_backup_ms") }
    static var lastLocalChangeMs: Int64 { prefs.long("last_local_change_ms") }

    static func link(uid: String, username: String, plixUserId: Int64, lastBackupMs: Int64) {
        prefs.edit { values in
            values["signed_in"] = .bool(true)
            values["uid"] = .string(uid)
            values["username"] = .string(username)
            values["plix_user_id"] = .long(plixUserId)
            values["last_backup_ms"] = .long(lastBackupMs)
            values["last_local_change_ms"] = .long(lastBackupMs)
        }
    }

    static func setLastBackup(_ ms: Int64) { prefs.setLong("last_backup_ms", ms) }
    static func markLocalChange() { prefs.setLong("last_local_change_ms", Clock.nowMs) }
    static func signOut() { prefs.clear() }
}

/// Cuenta PLIX (usuario + PIN) con respaldo y restauración en Firestore.
/// Port de FirestoreBackupManager / FirestoreBackupClient / BackgroundSync / FriendsRuntime.
@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    enum SyncState: Equatable { case idle, syncing, synced, failed(String) }

    @Published private(set) var isSignedIn = SessionStore.isSignedIn
    @Published private(set) var username = SessionStore.username
    @Published private(set) var plixUserId = SessionStore.plixUserId
    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var incomingRequests: [FriendRequest] = []
    @Published private(set) var restoredRevision = 0

    var plixUserIdLabel: String { SyncConfig.formatPlixUserId(plixUserId) }
    var cloudAvailable: Bool { CloudConfig.isConfigured }

    private var startupSyncDone = false
    private var heartbeatTask: Task<Void, Never>?
    private var incomingListener: ListenerRegistration?
    private var knownIncomingIds = Set<String>()
    private var incomingPrimed = false
    private var lastHeartbeatMs: Int64 = 0

    private init() {}

    // MARK: Inicio / cierre de sesión

    static func validate(username: String, pin: String) throws {
        if username.trimmingCharacters(in: .whitespaces).isEmpty { throw PlixError.message("Usuario obligatorio.") }
        if pin.isEmpty { throw PlixError.message("PIN obligatorio.") }
        if !pin.allSatisfy({ $0.isASCII && $0.isNumber }) { throw PlixError.message("El PIN solo puede contener números.") }
        if !(4...8).contains(pin.count) { throw PlixError.message("El PIN debe tener entre 4 y 8 dígitos.") }
    }

    /// Inicia sesión si el usuario existe; si no existe, crea la cuenta y sube los datos locales.
    func signIn(username rawUsername: String, pin: String) async throws {
        let username = rawUsername.trimmingCharacters(in: .whitespaces)
        try Self.validate(username: username, pin: pin)
        let db = try CloudConfig.requireDB()
        guard let auth = CloudConfig.auth else { throw PlixError.firebaseUnavailable }
        syncState = .syncing
        do {
            let sanitized = TextUtil.sanitizeUsername(username)
            let lookup = try await db.collection(SyncConfig.accounts).document(sanitized).getDocument()
            var display = username
            if lookup.exists, let stored = lookup.get("username") as? String, !stored.isEmpty { display = stored }

            let uid: String
            let created: Bool
            if lookup.exists {
                do {
                    uid = try await auth.signIn(withEmail: SyncConfig.email(username), password: SyncConfig.password(pin)).user.uid
                } catch {
                    let code = CloudError.authCode(error)
                    if code == CloudError.wrongPassword || code == CloudError.invalidCredential
                        || code == CloudError.emailAlreadyInUse || code == CloudError.userMismatch {
                        throw PlixError.message("El PIN es incorrecto.")
                    }
                    throw CloudError.map(error)
                }
                created = false
            } else {
                do {
                    uid = try await auth.createUser(withEmail: SyncConfig.email(username), password: SyncConfig.password(pin)).user.uid
                } catch {
                    if CloudError.authCode(error) == CloudError.emailAlreadyInUse {
                        throw PlixError.message("Este usuario ya está registrado.\nInicia sesión con tu PIN.")
                    }
                    throw CloudError.map(error)
                }
                created = true
            }
            try await completeAuthSession(db: db, uid: uid, username: display, created: created)
            Keychain.set(pin, for: "pin")
            syncState = .synced
            startupSyncDone = true
            startRuntime()
        } catch {
            let mapped = CloudError.map(error)
            syncState = .failed(mapped.localizedDescription)
            if !SessionStore.isSignedIn { try? auth.signOut() }
            throw mapped
        }
    }

    private func completeAuthSession(db: Firestore, uid: String, username: String, created: Bool) async throws {
        let sanitized = TextUtil.sanitizeUsername(username)
        let userRef = db.collection(SyncConfig.users).document(uid)
        try await userRef.setData(["username": username, "sanitizedUsername": sanitized, "updatedAt": Clock.nowMs], merge: true)
        try await db.collection(SyncConfig.accounts).document(sanitized).setData(
            ["username": username, "sanitizedUsername": sanitized, "uid": uid, "createdAt": Clock.nowMs], merge: true)
        let plixId = try await ensurePlixUserId(db: db, uid: uid, username: username)

        let profile = try await userRef.getDocument()
        let hasBackup = (profile.get("hasBackup") as? Bool) ?? false
        if created || !hasBackup {
            let timestamp = try await uploadAll(db: db, uid: uid)
            SessionStore.link(uid: uid, username: username, plixUserId: plixId, lastBackupMs: timestamp)
        } else {
            let metadata = try await userRef.collection(SyncConfig.metadata).document(SyncConfig.syncDoc).getDocument()
            let remoteUpload = FirestoreValue.long(metadata.get("lastUploadMs"))
            try await downloadAndApply(db: db, uid: uid)
            SessionStore.link(uid: uid, username: username, plixUserId: plixId, lastBackupMs: remoteUpload)
        }
        applySessionState()
        await syncProfileImagesFromRemote(db: db, uid: uid)
        await PublicProfileService.publishQuietly()
    }

    private func ensurePlixUserId(db: Firestore, uid: String, username: String) async throws -> Int64 {
        let sanitized = TextUtil.sanitizeUsername(username)
        let accountRef = db.collection(SyncConfig.accounts).document(sanitized)
        let counterRef = db.collection(SyncConfig.meta).document(SyncConfig.plixUserIdsDoc)
        let profileRef = db.collection(SyncConfig.users).document(uid)
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let account = try transaction.getDocument(accountRef)
                let existing = FirestoreValue.long(account.get("plixUserId"))
                if existing > 0 {
                    let label = SyncConfig.formatPlixUserId(existing)
                    transaction.setData(["uid": uid, "username": username, "sanitizedUsername": sanitized,
                                         "plixUserId": existing, "plixUserIdLabel": label],
                                        forDocument: db.collection(SyncConfig.plixUserIdIndex).document(String(existing)), merge: true)
                    return NSNumber(value: existing)
                }
                let counter = try transaction.getDocument(counterRef)
                let id = max(1, FirestoreValue.long(counter.get("nextId"), 1))
                let label = SyncConfig.formatPlixUserId(id)
                transaction.setData(["nextId": id + 1], forDocument: counterRef, merge: true)
                var accountPatch: [String: Any] = ["plixUserId": id, "plixUserIdLabel": label]
                if !account.exists {
                    accountPatch["username"] = username
                    accountPatch["sanitizedUsername"] = sanitized
                    accountPatch["uid"] = uid
                    accountPatch["createdAt"] = Clock.nowMs
                }
                transaction.setData(accountPatch, forDocument: accountRef, merge: true)
                transaction.setData(["plixUserId": id, "plixUserIdLabel": label], forDocument: profileRef, merge: true)
                transaction.setData(["uid": uid, "username": username, "sanitizedUsername": sanitized,
                                     "plixUserId": id, "plixUserIdLabel": label],
                                    forDocument: db.collection(SyncConfig.plixUserIdIndex).document(String(id)), merge: true)
                return NSNumber(value: id)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return (result as? NSNumber)?.int64Value ?? 0
    }

    /// Cierra sesión y borra del dispositivo los datos respaldados (igual que Android).
    func signOut() {
        stopRuntime(markOffline: true)
        for name in BackupPolicy.discoverNames() { PrefsRegistry.shared.prefs(name).clear() }
        Keychain.delete("pin")
        try? CloudConfig.auth?.signOut()
        SessionStore.signOut()
        incomingRequests = []
        knownIncomingIds = []
        syncState = .idle
        applySessionState()
        restoredRevision += 1
    }

    private func applySessionState() {
        isSignedIn = SessionStore.isSignedIn
        username = SessionStore.username
        plixUserId = SessionStore.plixUserId
    }

    // MARK: Respaldo

    private func uploadAll(db: Firestore, uid: String) async throws -> Int64 {
        let timestamp = Clock.nowMs
        let userRef = db.collection(SyncConfig.users).document(uid)
        let batch = db.batch()
        for name in BackupPolicy.discoverNames() {
            let payload = PrefsRegistry.shared.prefs(name).exportPayload()
            batch.setData(["payload": payload, "updatedAt": timestamp],
                          forDocument: userRef.collection(SyncConfig.prefs).document(name))
        }
        batch.setData(["lastUploadMs": timestamp, "lastSync": timestamp, "version": 1],
                      forDocument: userRef.collection(SyncConfig.metadata).document(SyncConfig.syncDoc))
        batch.setData(["hasBackup": true, "updatedAt": timestamp], forDocument: userRef, merge: true)
        try await batch.commit()
        return timestamp
    }

    /// Aplica el respaldo remoto; si algo falla, restaura el estado local anterior.
    private func downloadAndApply(db: Firestore, uid: String) async throws {
        let snapshot = try await db.collection(SyncConfig.users).document(uid).collection(SyncConfig.prefs).getDocuments()
        var remote: [(String, String)] = []
        for doc in snapshot.documents where BackupPolicy.shouldBackup(doc.documentID) {
            guard let payload = doc.get("payload") as? String, JSONUtil.object(from: payload) != nil else { continue }
            remote.append((doc.documentID, payload))
        }
        let names = Set(BackupPolicy.discoverNames()).union(remote.map(\.0))
        var rollback: [String: [String: PrefValue]] = [:]
        for name in names { rollback[name] = PrefsRegistry.shared.prefs(name).snapshot() }
        for (name, payload) in remote {
            let prefs = PrefsRegistry.shared.prefs(name)
            prefs.importPayload(payload)
            if JSONUtil.object(from: prefs.exportPayload()) == nil {
                for (restoreName, values) in rollback { PrefsRegistry.shared.prefs(restoreName).replaceAll(with: values) }
                throw PlixError.message("No se pudo restaurar el respaldo.\nTus datos locales no han sido modificados.")
            }
        }
        restoredRevision += 1
    }

    /// Botón "Guardar progreso".
    func saveNow() async throws {
        guard SessionStore.isSignedIn else { return }
        let db = try CloudConfig.requireDB()
        guard CloudConfig.currentUid == SessionStore.uid else {
            throw PlixError.message("Tu sesión expiró. Vuelve a iniciar sesión.")
        }
        syncState = .syncing
        do {
            let timestamp = try await uploadAll(db: db, uid: SessionStore.uid)
            SessionStore.setLastBackup(timestamp)
            syncState = .synced
            await PublicProfileService.publishQuietly()
        } catch {
            syncState = .failed("No se pudo guardar el progreso.\nTus datos locales no han sido modificados.")
            throw PlixError.message("No se pudo guardar el progreso.\nTus datos locales no han sido modificados.")
        }
    }

    /// Sincronización automática una vez por arranque (BackgroundSync en Android).
    /// Diferencia documentada: si falla por red no se cierra la sesión; se reintenta en el próximo arranque.
    func startupSync() async {
        guard !startupSyncDone, SessionStore.isSignedIn, let db = CloudConfig.db else { return }
        startupSyncDone = true
        guard CloudConfig.currentUid == SessionStore.uid else {
            syncState = .failed("Tu sesión expiró. Vuelve a iniciar sesión.")
            return
        }
        startRuntime()
        syncState = .syncing
        do {
            let uid = SessionStore.uid
            let metadata = try await db.collection(SyncConfig.users).document(uid)
                .collection(SyncConfig.metadata).document(SyncConfig.syncDoc).getDocument()
            let remote = FirestoreValue.long(metadata.get("lastUploadMs"))
            let lastBackup = SessionStore.lastBackupMs
            let localChange = SessionStore.lastLocalChangeMs
            let localNew = localChange > lastBackup
            let remoteNewer = remote > lastBackup
            if localNew && (!remoteNewer || localChange >= remote) {
                SessionStore.setLastBackup(try await uploadAll(db: db, uid: uid))
            } else if remoteNewer {
                try await downloadAndApply(db: db, uid: uid)
                SessionStore.setLastBackup(remote)
                SessionStore.link(uid: uid, username: SessionStore.username, plixUserId: SessionStore.plixUserId, lastBackupMs: remote)
            }
            await syncProfileImagesFromRemote(db: db, uid: uid)
            syncState = .synced
            await PublicProfileService.publishQuietly()
        } catch {
            syncState = .failed("Sin conexión con la nube. Tus datos se guardan en este dispositivo.")
        }
    }

    /// Al pasar a segundo plano: marca cambios locales pendientes y deja de aparecer en línea.
    func appDidEnterBackground() {
        if SessionStore.isSignedIn && SessionStore.lastLocalChangeMs <= SessionStore.lastBackupMs {
            SessionStore.markLocalChange()
        }
        stopHeartbeat()
        if SessionStore.isSignedIn { Task { await PresenceService.markOffline(uid: SessionStore.uid) } }
    }

    func appDidBecomeActive() {
        guard SessionStore.isSignedIn, CloudConfig.isConfigured else { return }
        startHeartbeat()
    }

    // MARK: Avatar / fondo remotos

    func pushProfileImage(_ kind: ProfileImageKind) {
        guard SessionStore.isSignedIn, let db = CloudConfig.db else { return }
        let store = kind.store
        guard let ref = store.current else { return }
        let updatedAt = store.updatedAt > 0 ? store.updatedAt : Clock.nowMs
        let payload: [String: Any] = [kind.field: FirestoreValue.avatarMap(ref), kind.field + "UpdatedAt": updatedAt]
        let uid = SessionStore.uid
        Task {
            try? await db.collection(SyncConfig.users).document(uid).setData(payload, merge: true)
            await PublicProfileService.publishQuietly()
        }
    }

    private func syncProfileImagesFromRemote(db: Firestore, uid: String) async {
        guard let doc = try? await db.collection(SyncConfig.users).document(uid).getDocument(), doc.exists else { return }
        for kind in ProfileImageKind.allCases {
            guard let remote = FirestoreValue.avatar(doc.get(kind.field)) else { continue }
            let remoteUpdated = FirestoreValue.long(doc.get(kind.field + "UpdatedAt"))
            if kind.store.current == nil || remoteUpdated > kind.store.updatedAt {
                kind.store.save(remote, updatedAt: max(remoteUpdated, 1))
            }
        }
    }

    // MARK: Amigos en tiempo de ejecución (FriendsRuntime)

    private func startRuntime() {
        guard SessionStore.isSignedIn, let db = CloudConfig.db else { return }
        startHeartbeat()
        incomingListener?.remove()
        let uid = SessionStore.uid
        incomingPrimed = false
        incomingListener = FriendsService.incomingQuery(db: db, uid: uid).addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot else { return }
            let requests = snapshot.documents.compactMap { FriendRequest(id: $0.documentID, data: $0.data()) }
                .sorted { $0.createdAt > $1.createdAt }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let fresh = requests.filter { !self.knownIncomingIds.contains($0.id) }
                self.knownIncomingIds.formUnion(requests.map(\.id))
                self.incomingRequests = requests
                if self.incomingPrimed, let newest = fresh.first { self.notifyFriendRequest(newest) }
                self.incomingPrimed = true
            }
        }
    }

    private func stopRuntime(markOffline: Bool) {
        stopHeartbeat()
        incomingListener?.remove()
        incomingListener = nil
        if markOffline, SessionStore.isSignedIn {
            let uid = SessionStore.uid
            Task { await PresenceService.markOffline(uid: uid) }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.heartbeatNow()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    func heartbeatNow() async {
        guard SessionStore.isSignedIn, CloudConfig.isConfigured else { return }
        let now = Clock.nowMs
        guard now - lastHeartbeatMs >= 20_000 else { return }
        lastHeartbeatMs = now
        await PresenceService.heartbeat(uid: SessionStore.uid, username: SessionStore.username)
    }

    func refreshIncoming(_ requests: [FriendRequest]) {
        incomingRequests = requests
        knownIncomingIds.formUnion(requests.map(\.id))
    }

    /// El permiso de notificaciones se pide recién cuando llega la primera solicitud de amistad.
    private func notifyFriendRequest(_ request: FriendRequest) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Nueva solicitud de amistad"
            content.body = "\(request.fromUsername) quiere ser tu amigo en PLIX."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "friend-\(request.id)", content: content, trigger: nil))
        }
    }
}

enum ProfileImageKind: CaseIterable {
    case avatar, backdrop

    var store: ProfileImageStore { self == .avatar ? .avatar : .backdrop }
    var field: String { self == .avatar ? "icon" : "backdrop" }
}
