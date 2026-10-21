import FirebaseFirestore
import Foundation

enum WatchPartyConfig {
    static let controlHostOnly = "HOST_ONLY"
    static let controlEveryone = "EVERYONE"
    static let statePlaying = "PLAYING"
    static let statePaused = "PAUSED"
    static let typeMovie = "movie"
    static let typeSeries = "series"
    static let syncSoftMs: Int64 = 750
    static let syncHardMs: Int64 = 2_000
    static let hostHeartbeatMs: Int64 = 4_000
    static let joinSyncTimeoutMs: Int64 = 8_000
    static let presenceStaleMs: Int64 = 60_000
    static let maxVoiceBytes = 500_000
    static let maxVoiceSeconds: TimeInterval = 30
}

struct WatchPartyRoom: Equatable {
    let roomId: String
    let roomCode: String
    let hostId: String
    let hostName: String
    let active: Bool
    let controlMode: String
    let contentId: Int
    let contentType: String
    let contentTitle: String
    let posterUrl: String
    let season: Int
    let episode: Int
    let preferredServerName: String
    let preferredServerLanguage: String
    let preferredServerUrl: String
    let playbackState: String
    let positionMs: Int64
    let durationMs: Int64
    let playbackSpeed: Double
    let updatedAtMs: Int64
    let updatedByUid: String
    let seq: Int64
    let participantCount: Int
    let createdAtMs: Int64
    let syncEpoch: Int64

    var hasContent: Bool { contentId > 0 && !contentType.isEmpty }
    var hasPreferredServer: Bool { !preferredServerName.isEmpty || !preferredServerUrl.isEmpty }
    var isReadyForGuests: Bool { hasContent && hasPreferredServer }
    var isPlaying: Bool { playbackState == WatchPartyConfig.statePlaying }
    var isSeries: Bool { contentType == WatchPartyConfig.typeSeries }

    init(roomId: String, data: [String: Any]) {
        self.roomId = roomId
        roomCode = FirestoreValue.string(data["roomCode"])
        let host = FirestoreValue.string(data["hostId"])
        hostId = host.isEmpty ? FirestoreValue.string(data["uid"]) : host
        let name = FirestoreValue.string(data["hostName"])
        hostName = name.isEmpty ? FirestoreValue.string(data["username"]) : name
        active = FirestoreValue.bool(data["isActive"], true)
        let mode = FirestoreValue.string(data["controlMode"])
        controlMode = mode.isEmpty ? WatchPartyConfig.controlHostOnly : mode
        contentId = Int(FirestoreValue.long(data["contentId"]))
        contentType = FirestoreValue.string(data["contentType"])
        contentTitle = FirestoreValue.string(data["contentTitle"])
        posterUrl = FirestoreValue.string(data["posterUrl"])
        season = Int(FirestoreValue.long(data["season"]))
        episode = Int(FirestoreValue.long(data["episode"]))
        preferredServerName = FirestoreValue.string(data["preferredServerName"])
        preferredServerLanguage = FirestoreValue.string(data["preferredServerLanguage"])
        preferredServerUrl = FirestoreValue.string(data["preferredServerUrl"])
        let state = FirestoreValue.string(data["playbackState"])
        playbackState = state.isEmpty ? WatchPartyConfig.statePaused : state
        positionMs = FirestoreValue.long(data["positionMs"])
        durationMs = FirestoreValue.long(data["durationMs"])
        playbackSpeed = FirestoreValue.double(data["playbackSpeed"], 1)
        if let stamp = data["serverTime"] as? Timestamp {
            updatedAtMs = Int64(stamp.dateValue().timeIntervalSince1970 * 1000)
        } else {
            updatedAtMs = FirestoreValue.long(data["updatedAtMs"], Clock.nowMs)
        }
        updatedByUid = FirestoreValue.string(data["updatedByUid"])
        seq = FirestoreValue.long(data["seq"])
        participantCount = Int(FirestoreValue.long(data["participantCount"], 1))
        createdAtMs = FirestoreValue.long(data["createdAtMs"], FirestoreValue.long(data["createdAt"]))
        syncEpoch = max(0, FirestoreValue.long(data["syncEpoch"]))
    }

    var mediaItem: MediaItem {
        MediaItem(id: contentId, title: contentTitle.isEmpty ? "Cine Virtual" : contentTitle, originalTitle: "",
                  overview: "", posterUrl: posterUrl, backdropUrl: "", year: "", rating: 0,
                  mediaType: isSeries ? .tv : .movie, genreIds: [])
    }
}

struct WatchPartyMessage: Identifiable, Equatable {
    static let typeText = "text"
    static let typeVoice = "voice"
    static let typeSticker = "sticker"
    static let typeJoin = "system_join"
    static let typeLeave = "system_leave"
    static let typeHostLeft = "system_host_left"

    let id: String
    let roomId: String
    let uid: String
    let displayName: String
    let type: String
    let text: String
    let voiceBase64: String
    let voiceDurationMs: Int64
    let createdAtMs: Int64

    var isVoice: Bool { type == Self.typeVoice && !voiceBase64.isEmpty }
    var isSticker: Bool { type == Self.typeSticker && !text.isEmpty }
    var isSystem: Bool { [Self.typeJoin, Self.typeLeave, Self.typeHostLeft].contains(type) }

    init?(id: String, data: [String: Any]) {
        guard FirestoreValue.bool(data["isWatchPartyMessage"]) else { return nil }
        self.id = id
        let chatRoom = FirestoreValue.string(data["chatRoomId"])
        roomId = chatRoom.isEmpty ? FirestoreValue.string(data["roomId"]) : chatRoom
        uid = FirestoreValue.string(data["uid"])
        var name = FirestoreValue.string(data["displayName"])
        if name.isEmpty { name = FirestoreValue.string(data["username"]) }
        displayName = name.isEmpty ? "Usuario" : name
        let rawType = FirestoreValue.string(data["type"])
        type = rawType.isEmpty ? Self.typeText : rawType
        text = FirestoreValue.string(data["text"])
        voiceBase64 = FirestoreValue.string(data["voiceBase64"])
        voiceDurationMs = FirestoreValue.long(data["voiceDurationMs"])
        createdAtMs = FirestoreValue.long(data["createdAtMs"], FirestoreValue.long(data["createdAt"]))
    }
}

struct WatchPartyParticipant: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let displayName: String
    let joinedAtMs: Int64
    let lastSeenMs: Int64
    let playbackSynced: Bool
    let syncedEpoch: Int64

    init?(data: [String: Any], cutoff: Int64) {
        guard FirestoreValue.bool(data["isWatchPartyPresence"]), FirestoreValue.bool(data["active"]) else { return nil }
        let lastSeen = FirestoreValue.long(data["lastSeenMs"])
        let uid = FirestoreValue.string(data["uid"])
        guard lastSeen >= cutoff, !uid.isEmpty else { return nil }
        self.uid = uid
        lastSeenMs = lastSeen
        joinedAtMs = FirestoreValue.long(data["joinedAtMs"], lastSeen)
        var name = FirestoreValue.string(data["displayName"])
        if name.isEmpty { name = FirestoreValue.string(data["username"]) }
        displayName = name.isEmpty ? "Usuario" : name
        playbackSynced = FirestoreValue.bool(data["playbackSynced"])
        syncedEpoch = FirestoreValue.long(data["syncedEpoch"], playbackSynced ? 0 : -1)
    }
}

/// Las salas, mensajes y presencia viven en `accounts` con banderas, igual que en Android
/// (así funcionan con las reglas de Firestore actuales del proyecto).
enum WatchPartyRoomClient {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generateCode() -> String {
        "LZ-" + String((0..<4).map { _ in alphabet.randomElement() ?? "A" })
    }

    static func normalizeCode(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: " ", with: "")
        if cleaned.count == 4, cleaned.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) { return "LZ-" + cleaned }
        return cleaned
    }

    static func docId(forCode code: String) -> String {
        TextUtil.sanitizeUsername("cine-" + normalizeCode(code))
    }

    private static func ref(_ roomId: String) throws -> DocumentReference {
        try CloudConfig.requireDB().collection(SyncConfig.accounts).document(roomId)
    }

    static func createRoom(hostId: String, hostName: String) async throws -> WatchPartyRoom {
        for _ in 0..<8 {
            let code = generateCode()
            let roomId = docId(forCode: code)
            let roomRef = try ref(roomId)
            let existing = try await roomRef.getDocument()
            if existing.exists, FirestoreValue.bool(existing.get("isActive")), FirestoreValue.bool(existing.get("isWatchParty")) {
                continue
            }
            let now = Clock.nowMs
            let room: [String: Any] = [
                "uid": hostId, "sanitizedUsername": roomId, "username": hostName.isEmpty ? "CineVirtual" : hostName,
                "createdAt": now, "isWatchParty": true, "roomId": roomId, "roomCode": code, "hostId": hostId,
                "hostName": hostName, "isActive": true, "controlMode": WatchPartyConfig.controlHostOnly,
                "contentId": 0, "contentType": "", "contentTitle": "", "posterUrl": "", "season": 0, "episode": 0,
                "preferredServerName": "", "preferredServerLanguage": "", "preferredServerUrl": "",
                "playbackState": WatchPartyConfig.statePaused, "positionMs": 0, "durationMs": 0, "playbackSpeed": 1.0,
                "updatedAtMs": now, "updatedByUid": hostId, "seq": 0, "syncEpoch": 0, "participantCount": 1,
                "createdAtMs": now, "serverTime": FieldValue.serverTimestamp()
            ]
            try await roomRef.setData(room)
            var local = room
            local["serverTime"] = nil
            return WatchPartyRoom(roomId: roomId, data: local)
        }
        throw PlixError.message("No se pudo generar un código libre.")
    }

    static func getRoom(_ roomId: String) async throws -> WatchPartyRoom {
        let snapshot = try await ref(roomId).getDocument()
        guard snapshot.exists, let data = snapshot.data(), FirestoreValue.bool(data["isWatchParty"]),
              FirestoreValue.bool(data["isActive"], true) else {
            throw PlixError.message("Sala no disponible")
        }
        return WatchPartyRoom(roomId: roomId, data: data)
    }

    static func joinRoom(code raw: String) async throws -> WatchPartyRoom {
        let code = normalizeCode(raw)
        guard !code.isEmpty else { throw PlixError.message("Código vacío") }
        return try await getRoom(docId(forCode: code))
    }

    static func closeRoom(_ roomId: String, hostId: String) async {
        guard let roomRef = try? ref(roomId) else { return }
        var updates: [String: Any] = ["isActive": false, "roomCode": "", "playbackState": WatchPartyConfig.statePaused,
                                      "updatedAtMs": Clock.nowMs, "serverTime": FieldValue.serverTimestamp(),
                                      "closedAtMs": Clock.nowMs]
        if !hostId.isEmpty { updates["updatedByUid"] = hostId }
        try? await roomRef.updateData(updates)
    }

    static func transferHost(_ roomId: String, previousHostId: String, newHostId: String, newHostName: String) async {
        guard let roomRef = try? ref(roomId) else { return }
        let name = newHostName.isEmpty ? "Anfitrión" : newHostName
        try? await roomRef.updateData(["hostId": newHostId, "hostName": name, "uid": newHostId, "username": name,
                                       "updatedAtMs": Clock.nowMs,
                                       "updatedByUid": previousHostId.isEmpty ? newHostId : previousHostId,
                                       "serverTime": FieldValue.serverTimestamp()])
    }

    /// El anfitrión sale: se pasa el control al participante más antiguo o se cierra la sala.
    static func handleHostLeave(room: WatchPartyRoom, hostId: String, hostName: String) async {
        await WatchPartyPresenceClient.markOffline(roomId: room.roomId, uid: hostId)
        let others = await WatchPartyPresenceClient.listActive(roomId: room.roomId, excluding: hostId)
        if let next = others.first {
            await transferHost(room.roomId, previousHostId: hostId, newHostId: next.uid, newHostName: next.displayName)
        } else {
            await closeRoom(room.roomId, hostId: hostId)
        }
        try? await WatchPartyChatClient.write(roomId: room.roomId, roomCode: room.roomCode, uid: hostId, displayName: hostName,
                                              type: WatchPartyMessage.typeHostLeft, text: "El anfitrión ha salido de la sala")
    }

    static func setContent(_ roomId: String, item: MediaItem, season: Int, episode: Int, hostId: String) async throws {
        try await ref(roomId).updateData([
            "contentId": item.id, "contentType": item.mediaType == .tv ? WatchPartyConfig.typeSeries : WatchPartyConfig.typeMovie,
            "contentTitle": item.title, "posterUrl": item.posterUrl, "season": max(0, season), "episode": max(0, episode),
            "preferredServerName": "", "preferredServerLanguage": "", "preferredServerUrl": "",
            "playbackState": WatchPartyConfig.statePaused, "positionMs": 0, "durationMs": 0, "playbackSpeed": 1.0,
            "updatedAtMs": Clock.nowMs, "updatedByUid": hostId, "seq": FieldValue.increment(Int64(1)),
            "serverTime": FieldValue.serverTimestamp()
        ])
    }

    static func setPreferredServer(_ roomId: String, server: StreamServer, hostId: String) async throws {
        try await ref(roomId).updateData([
            "preferredServerName": server.name, "preferredServerLanguage": server.language, "preferredServerUrl": server.url,
            "updatedAtMs": Clock.nowMs, "updatedByUid": hostId, "seq": FieldValue.increment(Int64(1)),
            "serverTime": FieldValue.serverTimestamp()
        ])
    }

    static func publishPlayback(_ roomId: String, uid: String, state: String, positionMs: Int64, durationMs: Int64,
                                speed: Double, syncEpoch: Int64) async {
        guard let roomRef = try? ref(roomId) else { return }
        try? await roomRef.updateData([
            "playbackState": state, "positionMs": max(0, positionMs), "durationMs": max(0, durationMs),
            "playbackSpeed": speed <= 0 ? 1.0 : speed, "syncEpoch": max(0, syncEpoch),
            "updatedAtMs": Clock.nowMs, "updatedByUid": uid, "seq": FieldValue.increment(Int64(1)),
            "serverTime": FieldValue.serverTimestamp()
        ])
    }

    static func listen(_ roomId: String, onRoom: @escaping (WatchPartyRoom) -> Void,
                       onError: @escaping (String) -> Void) -> ListenerRegistration? {
        guard let roomRef = try? ref(roomId) else { return nil }
        return roomRef.addSnapshotListener { snapshot, error in
            if let error {
                onError(error.localizedDescription.isEmpty ? "Error de sincronización" : error.localizedDescription)
                return
            }
            guard let snapshot, snapshot.exists, let data = snapshot.data() else {
                onError("La sala ya no existe")
                return
            }
            guard FirestoreValue.bool(data["isWatchParty"]) else {
                onError("Código inválido")
                return
            }
            onRoom(WatchPartyRoom(roomId: roomId, data: data))
        }
    }
}

enum WatchPartyChatClient {
    static func sendText(room: WatchPartyRoom, uid: String, displayName: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlixError.message("Mensaje vacío") }
        try await write(roomId: room.roomId, roomCode: room.roomCode, uid: uid, displayName: displayName,
                        type: WatchPartyMessage.typeText, text: String(trimmed.prefix(500)))
    }

    static func sendSticker(room: WatchPartyRoom, uid: String, displayName: String, key raw: String) async throws {
        guard let key = StickerCatalog.normalizeKey(raw), StickerCatalog.isImageFile(key) else {
            throw PlixError.message("Sticker inválido")
        }
        try await write(roomId: room.roomId, roomCode: room.roomCode, uid: uid, displayName: displayName,
                        type: WatchPartyMessage.typeSticker, text: key)
    }

    static func sendVoice(room: WatchPartyRoom, uid: String, displayName: String, audio: Data, durationMs: Int64) async throws {
        guard !audio.isEmpty else { throw PlixError.message("Audio vacío") }
        guard audio.count <= WatchPartyConfig.maxVoiceBytes else { throw PlixError.message("La nota de voz es demasiado larga") }
        try await write(roomId: room.roomId, roomCode: room.roomCode, uid: uid, displayName: displayName,
                        type: WatchPartyMessage.typeVoice, text: "", voiceBase64: audio.base64EncodedString(),
                        voiceDurationMs: max(0, durationMs))
    }

    static func sendPresenceEvent(room: WatchPartyRoom, uid: String, displayName: String, joined: Bool) async {
        let name = displayName.isEmpty ? "Alguien" : displayName
        try? await write(roomId: room.roomId, roomCode: room.roomCode, uid: uid, displayName: displayName,
                         type: joined ? WatchPartyMessage.typeJoin : WatchPartyMessage.typeLeave,
                         text: joined ? "\(name) se unió a la sala" : "\(name) salió de la sala")
    }

    static func write(roomId: String, roomCode: String, uid: String, displayName: String, type: String, text: String,
                      voiceBase64: String = "", voiceDurationMs: Int64 = 0) async throws {
        let db = try CloudConfig.requireDB()
        let random = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
        let messageId = TextUtil.sanitizeUsername("cmsg-" + random)
        let now = Clock.nowMs
        let name = displayName.isEmpty ? "Usuario" : displayName
        try await db.collection(SyncConfig.accounts).document(messageId).setData([
            "uid": uid, "sanitizedUsername": messageId, "username": name, "createdAt": now,
            "isWatchPartyMessage": true, "chatRoomId": roomId, "roomId": roomId, "roomCode": roomCode,
            "displayName": name, "type": type, "text": text, "voiceBase64": voiceBase64,
            "voiceDurationMs": voiceDurationMs, "createdAtMs": now
        ])
    }

    static func listen(_ roomId: String, onMessages: @escaping ([WatchPartyMessage], [WatchPartyMessage]) -> Void) -> ListenerRegistration? {
        guard let db = CloudConfig.db else { return nil }
        return db.collection(SyncConfig.accounts).whereField("chatRoomId", isEqualTo: roomId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let all = snapshot.documents.compactMap { WatchPartyMessage(id: $0.documentID, data: $0.data()) }
                    .sorted { $0.createdAtMs < $1.createdAtMs }
                let added = snapshot.documentChanges.filter { $0.type == .added }
                    .compactMap { WatchPartyMessage(id: $0.document.documentID, data: $0.document.data()) }
                onMessages(all, added)
            }
    }
}

enum WatchPartyPresenceClient {
    static func docId(roomId: String, uid: String) -> String {
        TextUtil.sanitizeUsername("cpres-\(roomId)-\(uid)")
    }

    private static func ref(roomId: String, uid: String) -> DocumentReference? {
        CloudConfig.db?.collection(SyncConfig.accounts).document(docId(roomId: roomId, uid: uid))
    }

    static func markOnline(roomId: String, uid: String, displayName: String, playbackSynced: Bool) async {
        guard let ref = ref(roomId: roomId, uid: uid) else { return }
        let now = Clock.nowMs
        var joined = now
        if let existing = try? await ref.getDocument(), existing.exists {
            let stored = FirestoreValue.long(existing.get("joinedAtMs"))
            if stored > 0 { joined = stored }
        }
        let name = displayName.isEmpty ? "Usuario" : displayName
        try? await ref.setData([
            "uid": uid, "sanitizedUsername": docId(roomId: roomId, uid: uid), "username": name, "displayName": name,
            "createdAt": now, "isWatchPartyPresence": true, "presenceRoomId": roomId, "active": true,
            "lastSeenMs": now, "joinedAtMs": joined, "playbackSynced": playbackSynced,
            "syncedEpoch": playbackSynced ? 0 : -1
        ])
    }

    static func markSynced(roomId: String, uid: String, displayName: String, epoch: Int64) async {
        guard let ref = ref(roomId: roomId, uid: uid) else { return }
        let updates: [String: Any] = ["playbackSynced": true, "syncedEpoch": max(0, epoch), "lastSeenMs": Clock.nowMs]
        do {
            try await ref.updateData(updates)
        } catch {
            await markOnline(roomId: roomId, uid: uid, displayName: displayName, playbackSynced: true)
            try? await ref.updateData(updates)
        }
    }

    static func heartbeat(roomId: String, uid: String, displayName: String) async {
        guard let ref = ref(roomId: roomId, uid: uid) else { return }
        var updates: [String: Any] = ["active": true, "lastSeenMs": Clock.nowMs]
        if !displayName.isEmpty {
            updates["displayName"] = displayName
            updates["username"] = displayName
        }
        do {
            try await ref.updateData(updates)
        } catch {
            await markOnline(roomId: roomId, uid: uid, displayName: displayName, playbackSynced: true)
        }
    }

    static func markOffline(roomId: String, uid: String) async {
        guard let ref = ref(roomId: roomId, uid: uid) else { return }
        try? await ref.updateData(["active": false, "playbackSynced": false, "syncedEpoch": -1, "lastSeenMs": Clock.nowMs])
    }

    static func listActive(roomId: String, excluding: String) async -> [WatchPartyParticipant] {
        guard let db = CloudConfig.db,
              let snapshot = try? await db.collection(SyncConfig.accounts).whereField("presenceRoomId", isEqualTo: roomId).getDocuments()
        else { return [] }
        let cutoff = Clock.nowMs - WatchPartyConfig.presenceStaleMs
        return snapshot.documents.compactMap { WatchPartyParticipant(data: $0.data(), cutoff: cutoff) }
            .filter { $0.uid != excluding }
            .sorted { $0.joinedAtMs < $1.joinedAtMs }
    }

    static func listen(_ roomId: String, onParticipants: @escaping ([WatchPartyParticipant]) -> Void) -> ListenerRegistration? {
        guard let db = CloudConfig.db else { return nil }
        return db.collection(SyncConfig.accounts).whereField("presenceRoomId", isEqualTo: roomId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let cutoff = Clock.nowMs - WatchPartyConfig.presenceStaleMs
                onParticipants(snapshot.documents.compactMap { WatchPartyParticipant(data: $0.data(), cutoff: cutoff) }
                    .sorted { $0.joinedAtMs < $1.joinedAtMs })
            }
    }
}

/// Port exacto de PlaybackSyncEngine.expectedPositionMs.
enum PlaybackSync {
    static func expectedPosition(_ room: WatchPartyRoom, now: Int64 = Clock.nowMs) -> Int64 {
        let position = max(0, room.positionMs)
        guard room.isPlaying else { return position }
        let elapsed = max(0, now - room.updatedAtMs)
        let speed = room.playbackSpeed <= 0 ? 1 : room.playbackSpeed
        var expected = position + Int64(Double(elapsed) * speed)
        if room.durationMs > 0 { expected = min(expected, room.durationMs) }
        return max(0, expected)
    }
}

/// Port de WatchPartyServerMatcher: encuentra en la lista del invitado el servidor elegido por el anfitrión.
enum WatchPartyServerMatcher {
    static func indexOf(_ servers: [StreamServer], name: String, language: String, url: String) -> Int? {
        guard !servers.isEmpty else { return nil }
        let wantUrl = normalizeURL(url)
        let wantId = videoId(url)
        let wantProvider = providerKey(url: url, name: name)
        let wantName = normalize(name)
        let wantLang = normalizeLanguage(language, name)

        if !wantUrl.isEmpty, let index = servers.firstIndex(where: { normalizeURL($0.url) == wantUrl }) { return index }
        if !wantId.isEmpty {
            if let index = servers.firstIndex(where: { server in
                guard videoId(server.url) == wantId else { return false }
                let provider = providerKey(url: server.url, name: server.name)
                return wantProvider.isEmpty || provider.isEmpty || related(wantProvider, provider)
            }) { return index }
            if let index = servers.firstIndex(where: { videoId($0.url) == wantId }) { return index }
        }
        if !wantName.isEmpty && !wantLang.isEmpty,
           let index = servers.firstIndex(where: { namesEqual(wantName, $0.name) && languagesMatch(wantLang, $0.language, $0.name) }) {
            return index
        }
        if !wantName.isEmpty {
            if let index = servers.firstIndex(where: { namesEqual(wantName, $0.name) }) { return index }
            if let index = servers.firstIndex(where: { server in
                let candidate = normalize(server.name)
                guard !candidate.isEmpty else { return false }
                let similar = candidate.contains(wantName) || wantName.contains(candidate) || coreName(wantName) == coreName(candidate)
                return similar && (wantLang.isEmpty || languagesMatch(wantLang, server.language, server.name))
            }) { return index }
        }
        if !wantProvider.isEmpty {
            var bestAny: Int?
            for (index, server) in servers.enumerated() where related(wantProvider, providerKey(url: server.url, name: server.name)) {
                if bestAny == nil { bestAny = index }
                if !wantLang.isEmpty && languagesMatch(wantLang, server.language, server.name) { return index }
            }
            if let bestAny { return bestAny }
        }
        var bestIndex: Int?
        var bestScore = 0
        let wantCore = coreName(wantName)
        for (index, server) in servers.enumerated() {
            var score = 0
            if !wantProvider.isEmpty && related(wantProvider, providerKey(url: server.url, name: server.name)) { score += 30 }
            let core = coreName(server.name)
            if !wantCore.isEmpty && !core.isEmpty {
                if wantCore == core { score += 25 } else if core.contains(wantCore) || wantCore.contains(core) { score += 15 }
            }
            if !wantLang.isEmpty && languagesMatch(wantLang, server.language, server.name) { score += 20 }
            if score > bestScore { bestScore = score; bestIndex = index }
        }
        return bestScore >= 35 ? bestIndex : nil
    }

    static func normalize(_ value: String) -> String {
        let folded = TextUtil.stripAccents(value.trimmingCharacters(in: .whitespaces).lowercased())
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func normalizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        guard let components = URLComponents(string: trimmed), let host = components.host else { return trimmed.lowercased() }
        let scheme = components.scheme?.lowercased() ?? "https"
        var path = components.path
        while path.hasSuffix("/") && path.count > 1 { path.removeLast() }
        path = path.replacingOccurrences(of: "/embed/", with: "/v/")
        return scheme + "://" + host.lowercased().replacingOccurrences(of: "www.", with: "") + path
    }

    static func videoId(_ raw: String) -> String {
        guard let path = URLComponents(string: raw.trimmingCharacters(in: .whitespaces))?.path, !path.isEmpty else { return "" }
        for part in path.split(separator: "/").reversed() {
            let lower = part.lowercased()
            if ["embed", "v", "e", "f", "d"].contains(lower) { continue }
            var value = String(part)
            if let dot = value.lastIndex(of: "."), dot > value.startIndex, value.distance(from: dot, to: value.endIndex) <= 5 {
                value = String(value[..<dot])
            }
            if value.count >= 4 { return value.lowercased() }
        }
        return ""
    }

    static func providerKey(url: String, name: String) -> String {
        let fromURL = url.isEmpty ? "" : normalize(StreamLinkRepository.nameFromURL(url))
        let key = fromURL.isEmpty ? coreName(name) : fromURL
        guard !key.isEmpty else { return "" }
        if key.contains("streamwish") || key.contains("swish") || key == "sw" { return "streamwish" }
        if ["vidhide", "minochinos", "filelions", "filemoon"].contains(where: key.contains) { return "vidhide" }
        if key.contains("goodstream") || key.contains("gscdn") { return "goodstream" }
        if key.contains("vimeos") { return "vimeos" }
        if key.contains("primeload") || key.contains("primecdn") { return "primeload" }
        if key.contains("abyss") || key.contains("hydrax") { return "abyss" }
        if key.contains("ok.ru") || key.contains("odnoklassniki") || key == "ok" { return "okru" }
        if key.contains("uqload") { return "uqload" }
        if key.contains("voe") { return "voe" }
        if key.contains("nupload") { return "nupload" }
        return key
    }

    private static func related(_ a: String, _ b: String) -> Bool {
        !a.isEmpty && !b.isEmpty && (a == b || a.contains(b) || b.contains(a))
    }

    private static func coreName(_ value: String) -> String {
        var name = normalize(value)
        guard !name.isEmpty else { return "" }
        for token in ["latino", "castellano", "subtitulado", "subtitulos", "subtitles", "english", "ingles", "espanol"] {
            name = name.replacingOccurrences(of: token, with: " ")
        }
        name = name.replacingOccurrences(of: " dual", with: " ").replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return normalize(name)
    }

    private static func namesEqual(_ want: String, _ serverName: String) -> Bool {
        let name = normalize(serverName)
        return !name.isEmpty && (want == name || coreName(want) == coreName(name))
    }

    private static func normalizeLanguage(_ language: String, _ name: String) -> String {
        let lang = normalize(language)
        if !lang.isEmpty { return lang }
        let n = normalize(name)
        if n.contains("latino") { return "latino" }
        if n.contains("castellano") { return "castellano" }
        if n.contains("subtit") { return "subtitulado" }
        if n.contains("english") || n.contains("ingles") { return "english" }
        return ""
    }

    private static func languagesMatch(_ want: String, _ language: String, _ name: String) -> Bool {
        let lang = normalizeLanguage(language, name)
        if lang.isEmpty { return normalize(name).contains(want) }
        return want == lang || want.contains(lang) || lang.contains(want) || aliases(want, lang)
    }

    private static func aliases(_ a: String, _ b: String) -> Bool {
        func latino(_ v: String) -> Bool { v.contains("latino") || v == "lat" }
        func castellano(_ v: String) -> Bool { v.contains("castellano") || v.contains("espanol") || v == "es" || v.contains("spain") }
        func subbed(_ v: String) -> Bool { v.contains("subtit") || v.contains("sub ") || v.hasSuffix(" sub") || v == "sub" || v.contains("subs") }
        func english(_ v: String) -> Bool { v.contains("english") || v.contains("ingles") || v == "en" || v.contains("vo ") }
        return (latino(a) && latino(b)) || (castellano(a) && castellano(b)) || (subbed(a) && subbed(b)) || (english(a) && english(b))
    }
}
