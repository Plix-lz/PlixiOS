import FirebaseFirestore
import Foundation

struct FriendRequest: Identifiable, Hashable {
    let id: String
    let fromUid: String
    let toUid: String
    let fromUsername: String
    let fromPlixUserIdLabel: String
    let fromAvatar: AvatarRef?
    let createdAt: Int64

    init?(id: String, data: [String: Any]) {
        let from = FirestoreValue.string(data["fromUid"])
        guard !from.isEmpty else { return nil }
        self.id = id
        fromUid = from
        toUid = FirestoreValue.string(data["toUid"])
        let name = FirestoreValue.string(data["fromUsername"])
        fromUsername = name.isEmpty ? "Usuario" : name
        fromPlixUserIdLabel = FirestoreValue.string(data["fromPlixUserIdLabel"])
        fromAvatar = FirestoreValue.avatar(data["fromAvatar"])
        createdAt = FirestoreValue.long(data["createdAt"])
    }
}

struct ProfileStats: Hashable {
    var achievements = 0
    var movies = 0
    var series = 0
    var episodes = 0
    var usageMs: Int64 = 0

    static func local() -> ProfileStats {
        let episodes = AchievementStore.set("played_episodes")
        var seriesIds = Set<String>()
        for key in episodes {
            let parts = key.split(separator: ":")
            if parts.count >= 2 { seriesIds.insert(String(parts[1])) }
        }
        return ProfileStats(achievements: AchievementStore.unlockedIds.count,
                            movies: AchievementStore.set("played_movies").count,
                            series: seriesIds.count,
                            episodes: episodes.count,
                            usageMs: AppUsageStore.totalMs)
    }

    var map: [String: Any] {
        ["achievements": achievements, "movies": movies, "series": series, "episodes": episodes, "usageMs": usageMs]
    }

    init(achievements: Int = 0, movies: Int = 0, series: Int = 0, episodes: Int = 0, usageMs: Int64 = 0) {
        self.achievements = achievements
        self.movies = movies
        self.series = series
        self.episodes = episodes
        self.usageMs = usageMs
    }

    init(map: Any?) {
        let data = map as? [String: Any] ?? [:]
        achievements = Int(FirestoreValue.long(data["achievements"]))
        movies = Int(FirestoreValue.long(data["movies"]))
        series = Int(FirestoreValue.long(data["series"]))
        episodes = Int(FirestoreValue.long(data["episodes"]))
        usageMs = FirestoreValue.long(data["usageMs"])
    }
}

struct PublicProfile: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    let username: String
    let plixUserId: Int64
    let plixUserIdLabel: String
    let icon: AvatarRef?
    let backdrop: AvatarRef?
    let stats: ProfileStats
    let bio: String
    let friendsCount: Int

    init(uid: String, data: [String: Any]) {
        self.uid = uid
        let name = FirestoreValue.string(data["username"])
        username = name.isEmpty ? "Usuario" : name
        plixUserId = FirestoreValue.long(data["plixUserId"])
        let label = FirestoreValue.string(data["plixUserIdLabel"])
        plixUserIdLabel = label.isEmpty ? SyncConfig.formatPlixUserId(plixUserId) : label
        icon = FirestoreValue.avatar(data["icon"])
        backdrop = FirestoreValue.avatar(data["backdrop"])
        stats = ProfileStats(map: data["stats"])
        bio = FirestoreValue.string(data["bio"])
        friendsCount = Int(FirestoreValue.long(data["friendsCount"], -1))
    }
}

struct FriendCard: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    var username: String
    var plixUserIdLabel: String
    var avatar: AvatarRef?
    var sinceMs: Int64
    var online = false
    var lastSeenMs: Int64 = 0
}

/// Perfil público (PublicProfileClient + PublicProfilePublisher).
enum PublicProfileService {
    static func publishQuietly() async {
        guard SessionStore.isSignedIn, let db = CloudConfig.db, CloudConfig.currentUid == SessionStore.uid else { return }
        let uid = SessionStore.uid
        let username = SessionStore.username
        let plixId = SessionStore.plixUserId
        let label = SyncConfig.formatPlixUserId(plixId)
        var data: [String: Any] = ["uid": uid, "username": username,
                                   "sanitizedUsername": TextUtil.sanitizeUsername(username),
                                   "plixUserId": plixId, "plixUserIdLabel": label,
                                   "updatedAt": Clock.nowMs, "stats": ProfileStats.local().map]
        if let icon = ProfileImageStore.avatar.current { data["icon"] = FirestoreValue.avatarMap(icon) }
        if let backdrop = ProfileImageStore.backdrop.current { data["backdrop"] = FirestoreValue.avatarMap(backdrop) }
        if ProfileBioStore.updatedAt > 0 {
            data["bio"] = ProfileBioStore.text
            data["bioUpdatedAt"] = ProfileBioStore.updatedAt
        }
        if let friends = try? await db.collection(SyncConfig.users).document(uid).collection(SyncConfig.friends).getDocuments() {
            data["friendsCount"] = friends.documents.count
        }
        try? await db.collection(SyncConfig.publicProfiles).document(uid).setData(data, merge: true)
        if plixId > 0 {
            try? await db.collection(SyncConfig.plixUserIdIndex).document(String(plixId)).setData(data, merge: true)
        }
        await FriendsService.syncMyCardToFriends()
    }

    static func fetch(uid: String) async throws -> PublicProfile? {
        let db = try CloudConfig.requireDB()
        let doc = try await db.collection(SyncConfig.publicProfiles).document(uid).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        return PublicProfile(uid: uid, data: data)
    }

    static func find(plixUserId raw: String) async throws -> PublicProfile? {
        let id = SyncConfig.parsePlixUserId(raw)
        guard id > 0 else { throw PlixError.message("ID PLIX inválido.") }
        let db = try CloudConfig.requireDB()
        let index = try await db.collection(SyncConfig.plixUserIdIndex).document(String(id)).getDocument()
        if index.exists, let data = index.data() {
            let uid = FirestoreValue.string(data["uid"])
            if !uid.isEmpty {
                if let profile = try? await fetch(uid: uid) { return profile }
                return PublicProfile(uid: uid, data: data)
            }
        }
        let accounts = try await db.collection(SyncConfig.accounts).whereField("plixUserId", isEqualTo: id).limit(to: 1).getDocuments()
        guard let account = accounts.documents.first else { return nil }
        let uid = FirestoreValue.string(account.get("uid"))
        guard !uid.isEmpty else { return nil }
        if let profile = try? await fetch(uid: uid) { return profile }
        return PublicProfile(uid: uid, data: account.data())
    }
}

/// Port de FriendsClient.
enum FriendsService {
    static func incomingQuery(db: Firestore, uid: String) -> Query {
        db.collection(SyncConfig.friendRequests)
            .whereField("toUid", isEqualTo: uid)
            .whereField("status", isEqualTo: "pending")
    }

    private static func myCard() -> (uid: String, username: String, plixId: Int64, label: String, avatar: [String: Any]?) {
        let plixId = SessionStore.plixUserId
        return (SessionStore.uid, SessionStore.username, plixId, SyncConfig.formatPlixUserId(plixId),
                ProfileImageStore.avatar.current.map(FirestoreValue.avatarMap))
    }

    private static func requireSession() throws -> Firestore {
        let db = try CloudConfig.requireDB()
        guard SessionStore.isSignedIn, CloudConfig.currentUid == SessionStore.uid else {
            throw PlixError.message("Inicia sesión para usar amigos.")
        }
        return db
    }

    static func areFriends(db: Firestore, _ a: String, _ b: String) async throws -> Bool {
        try await db.collection(SyncConfig.users).document(a).collection(SyncConfig.friends).document(b).getDocument().exists
    }

    static func sendRequest(to target: PublicProfile) async throws {
        let db = try requireSession()
        let me = myCard()
        if target.uid == me.uid { throw PlixError.message("No podés agregarte a vos mismo") }
        if try await areFriends(db: db, me.uid, target.uid) { throw PlixError.message("Ya son amigos") }
        let requests = db.collection(SyncConfig.friendRequests)
        let reverse = try await requests.whereField("fromUid", isEqualTo: target.uid)
            .whereField("toUid", isEqualTo: me.uid).whereField("status", isEqualTo: "pending").getDocuments()
        if let pending = reverse.documents.first, let request = FriendRequest(id: pending.documentID, data: pending.data()) {
            try await accept(request)
            return
        }
        let existing = try await requests.whereField("fromUid", isEqualTo: me.uid)
            .whereField("toUid", isEqualTo: target.uid).whereField("status", isEqualTo: "pending").getDocuments()
        if !existing.documents.isEmpty { throw PlixError.message("Ya enviaste una solicitud") }
        let now = Clock.nowMs
        var data: [String: Any] = ["fromUid": me.uid, "toUid": target.uid,
                                   "fromUsername": me.username, "toUsername": target.username,
                                   "fromPlixUserId": me.plixId, "fromPlixUserIdLabel": me.label,
                                   "toPlixUserId": target.plixUserId, "toPlixUserIdLabel": target.plixUserIdLabel,
                                   "status": "pending", "createdAt": now, "updatedAt": now]
        if let avatar = me.avatar { data["fromAvatar"] = avatar }
        _ = try await requests.addDocument(data: data)
    }

    static func listIncoming() async throws -> [FriendRequest] {
        let db = try requireSession()
        let snapshot = try await incomingQuery(db: db, uid: SessionStore.uid).getDocuments()
        return snapshot.documents.compactMap { FriendRequest(id: $0.documentID, data: $0.data()) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func accept(_ request: FriendRequest) async throws {
        let db = try requireSession()
        let me = myCard()
        let now = Clock.nowMs
        let other = try? await PublicProfileService.fetch(uid: request.fromUid)
        let batch = db.batch()
        batch.setData(["status": "accepted", "updatedAt": now],
                      forDocument: db.collection(SyncConfig.friendRequests).document(request.id), merge: true)
        var mine: [String: Any] = ["friendUid": request.fromUid,
                                   "username": other?.username ?? request.fromUsername,
                                   "plixUserId": other?.plixUserId ?? 0,
                                   "plixUserIdLabel": other?.plixUserIdLabel ?? request.fromPlixUserIdLabel,
                                   "sinceMs": now]
        if let avatar = other?.icon ?? request.fromAvatar { mine["avatar"] = FirestoreValue.avatarMap(avatar) }
        batch.setData(mine, forDocument: db.collection(SyncConfig.users).document(me.uid)
            .collection(SyncConfig.friends).document(request.fromUid), merge: true)
        var theirs: [String: Any] = ["friendUid": me.uid, "username": me.username, "plixUserId": me.plixId,
                                     "plixUserIdLabel": me.label, "sinceMs": now]
        if let avatar = me.avatar { theirs["avatar"] = avatar }
        batch.setData(theirs, forDocument: db.collection(SyncConfig.users).document(request.fromUid)
            .collection(SyncConfig.friends).document(me.uid), merge: true)
        try await batch.commit()
    }

    static func reject(_ request: FriendRequest) async throws {
        let db = try requireSession()
        try await db.collection(SyncConfig.friendRequests).document(request.id)
            .setData(["status": "rejected", "updatedAt": Clock.nowMs], merge: true)
    }

    static func listFriends() async throws -> [FriendCard] {
        let db = try requireSession()
        let uid = SessionStore.uid
        let snapshot = try await db.collection(SyncConfig.users).document(uid).collection(SyncConfig.friends).getDocuments()
        var cards: [FriendCard] = []
        for doc in snapshot.documents {
            let data = doc.data()
            let friendUid = FirestoreValue.string(data["friendUid"]).isEmpty ? doc.documentID : FirestoreValue.string(data["friendUid"])
            let name = FirestoreValue.string(data["username"])
            var card = FriendCard(uid: friendUid, username: name.isEmpty ? "Usuario" : name,
                                  plixUserIdLabel: FirestoreValue.string(data["plixUserIdLabel"]),
                                  avatar: FirestoreValue.avatar(data["avatar"]),
                                  sinceMs: FirestoreValue.long(data["sinceMs"]))
            if let profile = try? await PublicProfileService.fetch(uid: friendUid) {
                let changed = profile.username != card.username || profile.plixUserIdLabel != card.plixUserIdLabel
                    || (profile.icon != nil && profile.icon != card.avatar)
                card.username = profile.username
                card.plixUserIdLabel = profile.plixUserIdLabel
                if let icon = profile.icon { card.avatar = icon }
                if changed {
                    var patch: [String: Any] = ["username": card.username, "plixUserIdLabel": card.plixUserIdLabel,
                                                "plixUserId": profile.plixUserId]
                    if let avatar = card.avatar { patch["avatar"] = FirestoreValue.avatarMap(avatar) }
                    try? await doc.reference.setData(patch, merge: true)
                }
            }
            if let presence = await PresenceService.fetch(uid: friendUid) {
                card.online = presence.online
                card.lastSeenMs = presence.lastSeenMs
            }
            cards.append(card)
        }
        return cards.sorted { lhs, rhs in
            if lhs.online != rhs.online { return lhs.online }
            if lhs.lastSeenMs != rhs.lastSeenMs { return lhs.lastSeenMs > rhs.lastSeenMs }
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
    }

    /// Actualiza mi tarjeta dentro de la lista de amigos de cada amigo.
    static func syncMyCardToFriends() async {
        guard let db = try? requireSession() else { return }
        let me = myCard()
        guard let friends = try? await db.collection(SyncConfig.users).document(me.uid).collection(SyncConfig.friends).getDocuments() else { return }
        var patch: [String: Any] = ["friendUid": me.uid, "username": me.username, "plixUserId": me.plixId, "plixUserIdLabel": me.label]
        if let avatar = me.avatar { patch["avatar"] = avatar }
        for doc in friends.documents {
            try? await db.collection(SyncConfig.users).document(doc.documentID)
                .collection(SyncConfig.friends).document(me.uid).setData(patch, merge: true)
        }
    }
}

/// Presencia global de amigos (`presence/{uid}`).
enum PresenceService {
    struct Status { let online: Bool; let lastSeenMs: Int64 }

    static func heartbeat(uid: String, username: String) async {
        guard let db = CloudConfig.db, !uid.isEmpty else { return }
        try? await db.collection(SyncConfig.presence).document(uid)
            .setData(["uid": uid, "username": username, "active": true, "lastSeenMs": Clock.nowMs], merge: true)
    }

    static func markOffline(uid: String) async {
        guard let db = CloudConfig.db, !uid.isEmpty else { return }
        try? await db.collection(SyncConfig.presence).document(uid)
            .setData(["uid": uid, "active": false, "lastSeenMs": Clock.nowMs], merge: true)
    }

    static func fetch(uid: String) async -> Status? {
        guard let db = CloudConfig.db,
              let doc = try? await db.collection(SyncConfig.presence).document(uid).getDocument(), doc.exists else { return nil }
        let lastSeen = FirestoreValue.long(doc.get("lastSeenMs"))
        let active = FirestoreValue.bool(doc.get("active"))
        return Status(online: active && Clock.nowMs - lastSeen <= SyncConfig.presenceOnlineMs, lastSeenMs: lastSeen)
    }
}
