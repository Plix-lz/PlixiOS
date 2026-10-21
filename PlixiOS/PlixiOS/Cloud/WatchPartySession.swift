import AVFoundation
import FirebaseFirestore
import Foundation

/// Lo que el reproductor expone a la sincronización (equivale a WatchPartyManager.Host).
@MainActor
protocol WatchPartyPlayerBridge: AnyObject {
    var positionMs: Int64 { get }
    var durationMs: Int64 { get }
    var isPlaying: Bool { get }
    var playbackSpeed: Double { get }
    var isReadyToPlay: Bool { get }
    func applyPlay()
    func applyPause()
    func applySeek(_ positionMs: Int64)
    func applySpeed(_ speed: Double)
    func syncHoldChanged(_ holding: Bool)
}

/// Sala de Cine Virtual activa: rol, chat, participantes y sincronización del reproductor.
@MainActor
final class WatchPartySession: ObservableObject {
    static let shared = WatchPartySession()

    @Published private(set) var room: WatchPartyRoom?
    @Published private(set) var isHost = false
    @Published private(set) var messages: [WatchPartyMessage] = []
    @Published private(set) var participants: [WatchPartyParticipant] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var syncHolding = false
    @Published var lastError: String?
    var chatVisible = false { didSet { if chatVisible { unreadCount = 0 } } }

    private var roomListener: ListenerRegistration?
    private var chatListener: ListenerRegistration?
    private var presenceListener: ListenerRegistration?
    private var heartbeatTask: Task<Void, Never>?
    private var holdTimeoutTask: Task<Void, Never>?
    private weak var player: WatchPartyPlayerBridge?

    private var applyingRemote = false
    private var lastAppliedSeq: Int64 = -1
    private var currentSyncEpoch: Int64 = 0
    private var lastPublishedPositionMs: Int64 = -1
    private var lastGuestAckedEpoch: Int64 = -1
    private var guestCatchUpPending = false
    private var resumeAfterHold = false
    private var chatPrimed = false

    private init() {}

    var uid: String { SessionStore.uid }
    var displayName: String { SessionStore.username.isEmpty ? "Usuario" : SessionStore.username }
    var isActive: Bool { room != nil }

    private func requireAccount() throws {
        guard CloudConfig.isConfigured else { throw PlixError.firebaseUnavailable }
        guard SessionStore.isSignedIn, CloudConfig.currentUid == SessionStore.uid else {
            throw PlixError.message("Inicia sesión con tu cuenta PLIX para usar Cine Virtual.")
        }
    }

    // MARK: Crear / unirse / salir

    func createRoom() async throws -> WatchPartyRoom {
        try requireAccount()
        await leave()
        let created = try await WatchPartyRoomClient.createRoom(hostId: uid, hostName: displayName)
        enter(created, asHost: true)
        await WatchPartyPresenceClient.markOnline(roomId: created.roomId, uid: uid, displayName: displayName, playbackSynced: true)
        return created
    }

    func join(code: String) async throws {
        try requireAccount()
        let found = try await WatchPartyRoomClient.joinRoom(code: code)
        if room?.roomId == found.roomId { return }
        await leave()
        let host = found.hostId == uid
        enter(found, asHost: host)
        await WatchPartyPresenceClient.markOnline(roomId: found.roomId, uid: uid, displayName: displayName, playbackSynced: host)
        if !host { await WatchPartyChatClient.sendPresenceEvent(room: found, uid: uid, displayName: displayName, joined: true) }
    }

    func leave() async {
        guard let current = room else { return }
        let wasHost = isHost
        teardown()
        if wasHost {
            await WatchPartyRoomClient.handleHostLeave(room: current, hostId: uid, hostName: displayName)
        } else {
            await WatchPartyPresenceClient.markOffline(roomId: current.roomId, uid: uid)
            await WatchPartyChatClient.sendPresenceEvent(room: current, uid: uid, displayName: displayName, joined: false)
        }
    }

    private func enter(_ newRoom: WatchPartyRoom, asHost: Bool) {
        teardown()
        room = newRoom
        isHost = asHost
        currentSyncEpoch = newRoom.syncEpoch
        let roomId = newRoom.roomId
        roomListener = WatchPartyRoomClient.listen(roomId, onRoom: { [weak self] updated in
            Task { @MainActor in self?.handleRoom(updated) }
        }, onError: { [weak self] message in
            Task { @MainActor in self?.handleRoomError(message) }
        })
        chatListener = WatchPartyChatClient.listen(roomId) { [weak self] all, added in
            Task { @MainActor in self?.handleMessages(all, added: added) }
        }
        presenceListener = WatchPartyPresenceClient.listen(roomId) { [weak self] list in
            Task { @MainActor in self?.handleParticipants(list) }
        }
        startHeartbeat()
    }

    private func teardown() {
        roomListener?.remove()
        chatListener?.remove()
        presenceListener?.remove()
        roomListener = nil
        chatListener = nil
        presenceListener = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        clearHold(mayResume: false)
        room = nil
        isHost = false
        messages = []
        participants = []
        unreadCount = 0
        chatPrimed = false
        applyingRemote = false
        lastAppliedSeq = -1
        currentSyncEpoch = 0
        lastPublishedPositionMs = -1
        lastGuestAckedEpoch = -1
        guestCatchUpPending = false
    }

    private func handleRoomError(_ message: String) {
        lastError = message
        if message == "La sala ya no existe" || message == "Código inválido" { teardown() }
    }

    private func handleRoom(_ updated: WatchPartyRoom) {
        guard room != nil else { return }
        if !updated.active {
            lastError = "La sala se cerró."
            teardown()
            return
        }
        room = updated
        if updated.hostId == uid && !isHost {
            isHost = true
            currentSyncEpoch = max(currentSyncEpoch, updated.syncEpoch)
        } else if updated.hostId != uid && isHost {
            isHost = false
            clearHold(mayResume: false)
        }
        if isHost {
            currentSyncEpoch = max(currentSyncEpoch, updated.syncEpoch)
            lastAppliedSeq = max(lastAppliedSeq, updated.seq)
            return
        }
        applyRemoteRoom(updated)
    }

    private func handleMessages(_ all: [WatchPartyMessage], added: [WatchPartyMessage]) {
        messages = all
        if chatPrimed && !chatVisible {
            unreadCount += added.filter { $0.uid != uid && !$0.isSystem }.count
        }
        chatPrimed = true
    }

    private func handleParticipants(_ list: [WatchPartyParticipant]) {
        participants = list
        guard isHost, player != nil else { return }
        let epoch = max(currentSyncEpoch, room?.syncEpoch ?? 0)
        let waiting = list.contains { $0.uid != uid && $0.syncedEpoch < epoch }
        if waiting {
            let already = syncHolding
            beginHold(resumeFromPlaying: false)
            if !already { publish(state: WatchPartyConfig.statePaused) }
        } else {
            clearHold(mayResume: true)
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(WatchPartyConfig.hostHeartbeatMs) * 1_000_000)
                guard let self, !Task.isCancelled, let room = self.room else { return }
                tick += 1
                if self.isHost, let player = self.player, player.isPlaying, !self.syncHolding {
                    self.publish(state: WatchPartyConfig.statePlaying)
                }
                if tick % 5 == 0 {
                    await WatchPartyPresenceClient.heartbeat(roomId: room.roomId, uid: self.uid, displayName: self.displayName)
                }
            }
        }
    }

    // MARK: Contenido (anfitrión)

    func setContent(item: MediaItem, season: Int, episode: Int, server: StreamServer) async throws {
        guard let room, isHost else { throw PlixError.message("Solo el anfitrión puede elegir el contenido.") }
        try await WatchPartyRoomClient.setContent(room.roomId, item: item, season: season, episode: episode, hostId: uid)
        try await WatchPartyRoomClient.setPreferredServer(room.roomId, server: server, hostId: uid)
        ContentEntriesStore.salaVirtual.record(item)
    }

    func setPreferredServer(_ server: StreamServer) async {
        guard let room, isHost else { return }
        try? await WatchPartyRoomClient.setPreferredServer(room.roomId, server: server, hostId: uid)
    }

    // MARK: Chat

    func sendText(_ text: String) async throws {
        guard let room else { return }
        try await WatchPartyChatClient.sendText(room: room, uid: uid, displayName: displayName, text: text)
    }

    func sendSticker(_ key: String) async throws {
        guard let room else { return }
        try await WatchPartyChatClient.sendSticker(room: room, uid: uid, displayName: displayName, key: key)
    }

    func sendVoice(_ data: Data, durationMs: Int64) async throws {
        guard let room else { return }
        try await WatchPartyChatClient.sendVoice(room: room, uid: uid, displayName: displayName, audio: data, durationMs: durationMs)
    }

    // MARK: Reproductor

    func attach(player: WatchPartyPlayerBridge) {
        self.player = player
        lastPublishedPositionMs = -1
        guard let room else { return }
        if isHost {
            handleParticipants(participants)
        } else {
            guestCatchUpPending = true
            applyGuestCatchUp(room)
        }
    }

    func detach(player: WatchPartyPlayerBridge) {
        guard self.player === player else { return }
        clearHold(mayResume: false)
        self.player = nil
    }

    var canControlPlayback: Bool { room == nil || isHost || room?.isHostOnly == false }

    /// El reproductor del invitado avisa que ya cargó y quedó en la posición pedida.
    func playerBecameReady() {
        guard let room, !isHost, player != nil, guestCatchUpPending else { return }
        let epoch = room.syncEpoch
        guestCatchUpPending = false
        lastGuestAckedEpoch = max(lastGuestAckedEpoch, epoch)
        let roomId = room.roomId
        Task { await WatchPartyPresenceClient.markSynced(roomId: roomId, uid: uid, displayName: displayName, epoch: epoch) }
        applyGuestMirror(room, force: true)
    }

    func localPlay() { if !applyingRemote { publishLocal(WatchPartyConfig.statePlaying) } }
    func localPause() { if !applyingRemote { publishLocal(WatchPartyConfig.statePaused) } }

    func localSeek() {
        guard isHost, !applyingRemote, let player else { return }
        let position = player.positionMs
        let largeJump = lastPublishedPositionMs >= 0 && abs(position - lastPublishedPositionMs) >= WatchPartyConfig.syncHardMs
        if largeJump {
            currentSyncEpoch += 1
            beginHold(resumeFromPlaying: true)
            publish(state: WatchPartyConfig.statePaused)
            return
        }
        publish(state: syncHolding || !player.isPlaying ? WatchPartyConfig.statePaused : WatchPartyConfig.statePlaying)
    }

    func localSpeedChanged() {
        guard isHost, let player else { return }
        publish(state: player.isPlaying ? WatchPartyConfig.statePlaying : WatchPartyConfig.statePaused)
    }

    private func publishLocal(_ state: String) {
        guard isHost else { return }
        if syncHolding && state == WatchPartyConfig.statePlaying { return }
        publish(state: state)
    }

    private func publish(state: String) {
        guard let room, let player else { return }
        lastPublishedPositionMs = player.positionMs
        let roomId = room.roomId
        let uid = self.uid
        let position = player.positionMs
        let duration = player.durationMs
        let speed = player.playbackSpeed
        let epoch = currentSyncEpoch
        Task {
            await WatchPartyRoomClient.publishPlayback(roomId, uid: uid, state: state, positionMs: position,
                                                       durationMs: duration, speed: speed, syncEpoch: epoch)
        }
    }

    private func beginHold(resumeFromPlaying: Bool) {
        guard let player else { return }
        if !syncHolding {
            syncHolding = true
            resumeAfterHold = resumeFromPlaying || resumeAfterHold || player.isPlaying
            player.syncHoldChanged(true)
            runRemote { player.applyPause() }
            holdTimeoutTask?.cancel()
            holdTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(WatchPartyConfig.joinSyncTimeoutMs) * 1_000_000)
                guard !Task.isCancelled else { return }
                self?.clearHold(mayResume: true)
            }
        } else if resumeFromPlaying {
            resumeAfterHold = true
            runRemote { player.applyPause() }
        }
    }

    private func clearHold(mayResume: Bool) {
        holdTimeoutTask?.cancel()
        holdTimeoutTask = nil
        guard syncHolding else { return }
        syncHolding = false
        let resume = mayResume && resumeAfterHold
        resumeAfterHold = false
        player?.syncHoldChanged(false)
        if resume, isHost, let player {
            runRemote { player.applyPlay() }
            publish(state: WatchPartyConfig.statePlaying)
        }
    }

    private func runRemote(_ action: () -> Void) {
        applyingRemote = true
        action()
        applyingRemote = false
    }

    private func applyRemoteRoom(_ updated: WatchPartyRoom) {
        guard player != nil else { return }
        if updated.syncEpoch > lastGuestAckedEpoch {
            guestCatchUpPending = true
            applyGuestCatchUp(updated)
            if player?.isReadyToPlay == true { playerBecameReady() }
            return
        }
        if guestCatchUpPending {
            applyGuestCatchUp(updated)
            return
        }
        applyGuestMirror(updated, force: false)
    }

    private func applyGuestCatchUp(_ updated: WatchPartyRoom) {
        guard let player else { return }
        let target = updated.isPlaying ? PlaybackSync.expectedPosition(updated) : max(0, updated.positionMs)
        lastAppliedSeq = max(lastAppliedSeq, updated.seq)
        runRemote {
            player.applySeek(target)
            player.applyPause()
        }
    }

    private func applyGuestMirror(_ updated: WatchPartyRoom, force: Bool) {
        guard let player else { return }
        if !force && updated.seq <= lastAppliedSeq { return }
        lastAppliedSeq = max(lastAppliedSeq, updated.seq)
        let expected = PlaybackSync.expectedPosition(updated)
        let drift = abs(expected - player.positionMs)
        let targetSpeed = updated.playbackSpeed <= 0 ? 1 : updated.playbackSpeed
        let shouldPlay = updated.isPlaying
        let needSeek = drift >= (shouldPlay ? WatchPartyConfig.syncHardMs : WatchPartyConfig.syncSoftMs)
        runRemote {
            if abs(player.playbackSpeed - targetSpeed) > 0.01 { player.applySpeed(targetSpeed) }
            if needSeek { player.applySeek(expected) }
            if shouldPlay != player.isPlaying || force {
                if shouldPlay { player.applyPlay() } else { player.applyPause() }
            }
        }
    }
}

extension WatchPartyRoom {
    var isHostOnly: Bool { controlMode != WatchPartyConfig.controlEveryone }
}

/// Notas de voz del chat: AAC 16 kHz mono 48 kbps en MPEG-4 (mismo formato que Android), máximo 30 s.
/// El permiso de micrófono se pide recién al tocar "grabar".
@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("plix_voice_note.m4a")

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    func start() async throws {
        guard await requestPermission() else {
            throw PlixError.message("Permite el acceso al micrófono en Ajustes para enviar notas de voz.")
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000,
                                       AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.delegate = self
        guard recorder.record(forDuration: WatchPartyConfig.maxVoiceSeconds) else {
            throw PlixError.message("No se pudo iniciar la grabación.")
        }
        self.recorder = recorder
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                self.elapsed = recorder.currentTime
            }
        }
    }

    /// Detiene y devuelve el audio (nil si se canceló o duró menos de medio segundo).
    func stop(send: Bool) -> (Data, Int64)? {
        let duration = max(recorder?.currentTime ?? 0, elapsed)
        limitReached = false
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard send, duration >= 0.5, let data = try? Data(contentsOf: fileURL) else { return nil }
        return (data, Int64(duration * 1000))
    }

    /// Se activa cuando la grabación llega al límite de 30 s; la UI la envía automáticamente.
    @Published private(set) var limitReached = false

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if self.isRecording { self.limitReached = true }
        }
    }
}

/// Reproduce notas de voz recibidas (base64 → archivo temporal → AVAudioPlayer).
@MainActor
final class VoiceNotePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoiceNotePlayer()
    @Published private(set) var playingId: String?
    private var player: AVAudioPlayer?

    func toggle(_ message: WatchPartyMessage) {
        if playingId == message.id {
            player?.stop()
            playingId = nil
            return
        }
        guard let data = Data(base64Encoded: message.voiceBase64), let created = try? AVAudioPlayer(data: data) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.stop()
        created.delegate = self
        created.play()
        player = created
        playingId = message.id
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingId = nil }
    }
}
