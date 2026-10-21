import AVFoundation
import Combine
import Foundation
import UIKit

/// Lo necesario para abrir el reproductor.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let item: MediaItem
    let season: Int
    let episode: Int
    let servers: [StreamServer]
    let preResolved: CapturedStream?
    let watchParty: Bool

    var isSeries: Bool { item.mediaType == .tv }
    var progressKey: String {
        isSeries ? PlaybackProgressStore.episodeKey(item.id, season, episode) : PlaybackProgressStore.movieKey(item.id)
    }
}

@MainActor
final class ServerListBox {
    var servers: [StreamServer] = []
}

struct QualityOption: Identifiable, Hashable {
    let label: String
    let peakBitRate: Double
    var id: String { label }
}

@MainActor
final class PlayerModel: ObservableObject, WatchPartyPlayerBridge {
    enum Phase: Equatable {
        case resolving(String)
        case playing
        case failed(String)
    }

    static let minResumeMs: Int64 = 10_000
    static let endMarginMs: Int64 = 30_000

    @Published private(set) var request: PlaybackRequest
    @Published private(set) var phase: Phase = .resolving("Preparando…")
    @Published private(set) var currentIndex = 0
    @Published private(set) var isPlayingState = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var buffering = false
    @Published private(set) var speed: Double = 1
    @Published private(set) var resumeOffer: Int64?
    @Published private(set) var episodes: [EpisodeItem] = []
    @Published private(set) var qualities: [QualityOption] = []
    @Published private(set) var selectedQuality = "Auto"
    @Published private(set) var audioOptions: [AVMediaSelectionOption] = []
    @Published private(set) var subtitleOptions: [AVMediaSelectionOption] = []
    @Published private(set) var selectedAudio: AVMediaSelectionOption?
    @Published private(set) var selectedSubtitle: AVMediaSelectionOption?
    @Published private(set) var reachedEnd = false
    @Published private(set) var syncHold = false
    @Published var locked = false
    @Published var brightness: Double = Double(UIScreen.main.brightness)

    let player = AVPlayer()
    let capture = StreamCaptureEngine()
    private var startTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var itemObservers: [NSKeyValueObservation] = []
    private var cancellables = Set<AnyCancellable>()
    private var startedReported = false
    private var completedReported = false
    private var readyHandled = false
    private var pendingSeekMs: Int64?
    private let originalBrightness = UIScreen.main.brightness

    var server: StreamServer? { request.servers.indices.contains(currentIndex) ? request.servers[currentIndex] : nil }
    var hasNextEpisode: Bool { nextEpisode != nil }

    init(request: PlaybackRequest) {
        self.request = request
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true
        let saved = PlayerUIStore.brightness
        if saved >= 0 { brightness = saved }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time) }
        }
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] note in
                Task { @MainActor in
                    guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                    self.handleEnded()
                }
            }
            .store(in: &cancellables)
        capture.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlayingState = status == .playing
                self?.buffering = status == .waitingToPlayAtSpecifiedRate
            }
            .store(in: &cancellables)
    }

    // MARK: Ciclo de vida

    func start() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        UIScreen.main.brightness = CGFloat(brightness)
        if request.watchParty { WatchPartySession.shared.attach(player: self) }
        loadEpisodesIfNeeded()
        tryServer(at: 0)
    }

    func stop() {
        saveProgress()
        startTask?.cancel()
        capture.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        itemObservers.removeAll()
        cancellables.removeAll()
        UIScreen.main.brightness = originalBrightness
        if request.watchParty { WatchPartySession.shared.detach(player: self) }
    }

    // MARK: Cola de servidores

    func selectServer(_ index: Int) {
        guard request.servers.indices.contains(index) else { return }
        saveProgress()
        tryServer(at: index, userChoice: true)
        if request.watchParty, WatchPartySession.shared.isHost {
            let chosen = request.servers[index]
            Task { await WatchPartySession.shared.setPreferredServer(chosen) }
        }
    }

    func retry() { tryServer(at: currentIndex, userChoice: true) }

    func revealCapture() { capture.revealForUser() }

    private func tryServer(at index: Int, userChoice: Bool = false) {
        startTask?.cancel()
        capture.cancel()
        guard request.servers.indices.contains(index) else {
            phase = .failed("Ningún servidor respondió. Prueba con otro idioma o más tarde.")
            return
        }
        currentIndex = index
        let server = request.servers[index]
        let first = index == 0 && !userChoice
        phase = .resolving("Conectando con \(server.name)…")
        startTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.resolve(server, first: first, userChoice: userChoice || index == 0)
            guard !Task.isCancelled else { return }
            if let stream {
                self.play(stream)
            } else {
                self.tryServer(at: index + 1)
            }
        }
    }

    private func resolve(_ server: StreamServer, first: Bool, userChoice: Bool) async -> CapturedStream? {
        if first, let pre = request.preResolved { return pre }
        if server.directStream || StreamURL.isPlayableStream(server.url) {
            return CapturedStream(url: server.url, referer: "", embedUrl: "",
                                  headers: StreamHeaders.build(streamURL: server.url, referer: nil, embedURL: nil, cookies: nil))
        }
        if PelixplayHLSResolver.isExtractable(server), let stream = await PelixplayHLSResolver.extract(server.url) {
            return stream
        }
        if Task.isCancelled { return nil }
        let family = ServerFamily.from(url: server.url, label: server.name)
        let visible = ServerChain.needsVisibleCapture(server.url, server.name)
        let timeout = family.captureTimeout(userChoice: userChoice, protected: ServerChain.isProtected(server.url, server.name))
        phase = .resolving(visible ? "Este servidor puede pedir verificación. Toca el video si aparece." : "Buscando el video en \(server.name)…")
        return await capture.capture(embed: server.url, label: server.name, timeout: visible ? max(timeout, 45) : timeout, visible: visible)
    }

    private func play(_ stream: CapturedStream) {
        // AVPlayer no reproduce DASH (.mpd): se pasa directo al siguiente servidor.
        guard let url = URL(string: stream.url), !StreamURL.isDash(stream.url) else {
            tryServer(at: currentIndex + 1)
            return
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 20
        readyHandled = false
        itemObservers = [
            item.observe(\.status, options: [.new]) { [weak self] observed, _ in
                Task { @MainActor in self?.itemStatusChanged(observed) }
            }
        ]
        player.replaceCurrentItem(with: item)
        player.rate = 0
        loadTracks(asset)
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .failed:
            tryServer(at: currentIndex + 1)
        case .readyToPlay:
            guard !readyHandled else { return }
            readyHandled = true
            phase = .playing
            duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
            reportStarted()
            if let pending = pendingSeekMs {
                pendingSeekMs = nil
                seek(toMs: pending, publish: false)
            }
            if request.watchParty {
                WatchPartySession.shared.playerBecameReady()
                return
            }
            let saved = PlaybackProgressStore.position(request.progressKey)
            if saved >= Self.minResumeMs && (duration <= 0 || Double(saved) / 1000 < duration - Double(Self.endMarginMs) / 1000) {
                resumeOffer = saved
            } else {
                player.play()
            }
        default:
            break
        }
    }

    func answerResume(continueFromSaved: Bool) {
        if continueFromSaved, let offset = resumeOffer {
            seek(toMs: offset, publish: false)
        } else {
            PlaybackProgressStore.clearPosition(request.progressKey)
        }
        resumeOffer = nil
        player.play()
    }

    // MARK: Progreso / logros

    private func reportStarted() {
        guard !startedReported else { return }
        startedReported = true
        let item = request.item
        ContentEntriesStore.history.record(item)
        PlaybackProgressStore.markContentStarted(item.id, series: request.isSeries)
        if request.isSeries { PlaybackProgressStore.markEpisodeStarted(item.id, request.season, request.episode) }
        AchievementManager.shared.onPlaybackStarted(contentId: item.id, series: request.isSeries,
                                                    season: request.season, episode: request.episode)
    }

    private func tick(_ time: CMTime) {
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        position = seconds
        if let item = player.currentItem, item.duration.seconds.isFinite { duration = item.duration.seconds }
        if isPlayingState { saveProgress() }
    }

    private func saveProgress() {
        guard phase == .playing, resumeOffer == nil else { return }
        let positionMs = Int64(position * 1000)
        let durationMs = Int64(duration * 1000)
        if durationMs > 0 && positionMs >= durationMs - Self.endMarginMs {
            PlaybackProgressStore.clearPosition(request.progressKey)
            reportCompleted()
        } else if positionMs >= Self.minResumeMs {
            PlaybackProgressStore.savePosition(request.progressKey, positionMs)
        }
    }

    private func reportCompleted() {
        guard !completedReported else { return }
        completedReported = true
        AchievementManager.shared.onPlaybackCompleted(contentId: request.item.id, series: request.isSeries,
                                                      season: request.season, episode: request.episode)
    }

    private func handleEnded() {
        PlaybackProgressStore.clearPosition(request.progressKey)
        reportCompleted()
        reachedEnd = true
    }

    // MARK: Controles

    func togglePlay() {
        guard canControl else { return }
        if isPlayingState { applyPause(); WatchPartySession.shared.localPause() }
        else { applyPlay(); WatchPartySession.shared.localPlay() }
    }

    func skip(_ seconds: Double) {
        guard canControl else { return }
        seek(toMs: Int64(max(0, position + seconds) * 1000), publish: true)
    }

    func scrub(to seconds: Double) {
        guard canControl else { return }
        seek(toMs: Int64(seconds * 1000), publish: true)
    }

    private func seek(toMs ms: Int64, publish: Bool) {
        let target = CMTime(value: ms, timescale: 1000)
        position = Double(ms) / 1000
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600)) { _ in
            Task { @MainActor in
                if publish && self.request.watchParty { WatchPartySession.shared.localSeek() }
            }
        }
    }

    func setSpeed(_ value: Double) {
        guard canControl else { return }
        applySpeed(value)
        WatchPartySession.shared.localSpeedChanged()
    }

    func setBrightness(_ value: Double) {
        brightness = min(1, max(0.05, value))
        UIScreen.main.brightness = CGFloat(brightness)
        PlayerUIStore.setBrightness(brightness)
    }

    var canControl: Bool { !request.watchParty || WatchPartySession.shared.canControlPlayback }

    // MARK: Pistas y calidad

    private func loadTracks(_ asset: AVURLAsset) {
        Task { [weak self] in
            let audible = try? await asset.loadMediaSelectionGroup(for: .audible)
            let legible = try? await asset.loadMediaSelectionGroup(for: .legible)
            let variants = (try? await asset.load(.variants)) ?? []
            guard let self else { return }
            self.audioOptions = audible?.options ?? []
            self.subtitleOptions = legible?.options ?? []
            self.selectedAudio = nil
            self.selectedSubtitle = nil
            var options: [QualityOption] = [QualityOption(label: "Auto", peakBitRate: 0)]
            var seenHeights = Set<Int>()
            for variant in variants.sorted(by: { ($0.peakBitRate ?? 0) > ($1.peakBitRate ?? 0) }) {
                guard let height = variant.videoAttributes?.presentationSize.height, height > 0,
                      let rate = variant.peakBitRate else { continue }
                let rounded = Int(height)
                if seenHeights.insert(rounded).inserted {
                    options.append(QualityOption(label: "\(rounded)p", peakBitRate: rate))
                }
            }
            self.qualities = options.count > 1 ? options : []
            self.selectedQuality = "Auto"
            self.player.currentItem?.preferredPeakBitRate = 0
        }
    }

    func selectQuality(_ option: QualityOption) {
        player.currentItem?.preferredPeakBitRate = option.peakBitRate
        selectedQuality = option.label
    }

    func selectAudio(_ option: AVMediaSelectionOption) {
        guard let item = player.currentItem else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            item.select(option, in: group)
            selectedAudio = option
        }
    }

    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let item = player.currentItem else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) else { return }
            item.select(option, in: group)
            selectedSubtitle = option
        }
    }

    // MARK: Episodios

    private func loadEpisodesIfNeeded() {
        guard request.isSeries, request.season > 0 else { return }
        let id = request.item.id
        let season = request.season
        Task { [weak self] in
            let list = (try? await TMDBClient.shared.seasonEpisodes(seriesId: id, season: season)) ?? []
            self?.episodes = list
        }
    }

    var nextEpisode: EpisodeItem? {
        guard request.isSeries, let index = episodes.firstIndex(where: { $0.episode == request.episode }),
              episodes.indices.contains(index + 1) else { return nil }
        return episodes[index + 1]
    }

    /// Carga los servidores del episodio elegido y reinicia la reproducción.
    func playEpisode(_ episode: EpisodeItem) {
        guard !request.watchParty || WatchPartySession.shared.isHost else { return }
        saveProgress()
        startTask?.cancel()
        capture.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        phase = .resolving("Buscando servidores del episodio \(episode.episode)…")
        let item = request.item
        let watchParty = request.watchParty
        startTask = Task { [weak self] in
            let box = ServerListBox()
            await StreamLinkRepository.shared.fetchProgressive(contentId: item.id, isSeries: true, season: episode.season,
                                                               episode: episode.episode) { servers, _ in
                box.servers = servers
            }
            let found = box.servers
            guard let self, !Task.isCancelled else { return }
            let preferred = self.server.map(LanguageGroup.of) ?? .latino
            let sorted = ServerChain.sortForPlayback(found)
            let ordered = sorted.filter { LanguageGroup.of($0) == preferred } + sorted.filter { LanguageGroup.of($0) != preferred }
            guard !ordered.isEmpty else {
                self.phase = .failed("No hay servidores para este episodio.")
                return
            }
            self.request = PlaybackRequest(item: item, season: episode.season, episode: episode.episode,
                                           servers: ordered, preResolved: nil, watchParty: watchParty)
            self.startedReported = false
            self.completedReported = false
            self.reachedEnd = false
            self.position = 0
            self.duration = 0
            if watchParty, let first = ordered.first {
                try? await WatchPartySession.shared.setContent(item: item, season: episode.season, episode: episode.episode, server: first)
            }
            self.tryServer(at: 0)
        }
    }

    // MARK: WatchPartyPlayerBridge

    var positionMs: Int64 { Int64(max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0) * 1000) }
    var durationMs: Int64 { Int64(max(0, duration) * 1000) }
    var isPlaying: Bool { player.rate != 0 }
    var playbackSpeed: Double { speed }
    var isReadyToPlay: Bool { player.currentItem?.status == .readyToPlay }

    func applyPlay() {
        resumeOffer = nil
        player.playImmediately(atRate: Float(speed))
    }

    func applyPause() { player.pause() }

    func applySeek(_ positionMs: Int64) {
        if isReadyToPlay { seek(toMs: positionMs, publish: false) } else { pendingSeekMs = positionMs }
    }

    func applySpeed(_ value: Double) {
        speed = value
        if player.rate != 0 { player.rate = Float(value) }
    }

    func syncHoldChanged(_ holding: Bool) { syncHold = holding }
}
