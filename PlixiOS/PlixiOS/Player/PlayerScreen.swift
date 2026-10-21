import AVFoundation
import AVKit
import SwiftUI
import WebKit

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    final class SurfaceView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: SurfaceView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

/// Botón nativo de AirPlay (reemplaza a Chromecast de Android).
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = UIColor(Color.plixPrimary)
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct CaptureWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct PlayerScreen: View {
    @StateObject private var model: PlayerModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var watchParty: WatchPartySession
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubbing: Double?
    @State private var showSettings = false
    @State private var showEpisodes = false
    @State private var showServers = false
    @State private var showChat = false

    init(request: PlaybackRequest) {
        _model = StateObject(wrappedValue: PlayerModel(request: request))
    }

    private var capture: StreamCaptureEngine { model.capture }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(player: model.player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }

            if model.phase != .playing { phaseOverlay }

            if capture.needsUserInteraction { captureOverlay }

            if model.phase == .playing && (controlsVisible || model.locked) { controls }

            if model.syncHold {
                banner("Pausado: esperando que todos carguen el mismo tiempo…")
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            AppDelegate.setOrientation(.landscape)
            model.start()
            scheduleHide()
        }
        .onDisappear {
            model.stop()
            AppDelegate.setOrientation(.portrait)
        }
        .confirmationDialog("Continuar viendo", isPresented: Binding(get: { model.resumeOffer != nil }, set: { shown in
            if !shown && model.resumeOffer != nil { model.answerResume(continueFromSaved: true) }
        }),
                            titleVisibility: .visible) {
            Button("Continuar") { model.answerResume(continueFromSaved: true) }
            Button("Desde el inicio") { model.answerResume(continueFromSaved: false) }
        } message: {
            Text("Dejaste este contenido en \(TextUtil.formatDuration(ms: model.resumeOffer ?? 0)). ¿Cómo quieres reproducirlo?")
        }
        .sheet(isPresented: $showSettings) { PlayerSettingsSheet(model: model) }
        .sheet(isPresented: $showEpisodes) { PlayerEpisodesSheet(model: model) }
        .sheet(isPresented: $showServers) { PlayerServersSheet(model: model) }
        .sheet(isPresented: $showChat) { WatchPartyChatView().presentationDetents([.medium, .large]) }
    }

    private var title: String {
        let request = model.request
        return request.isSeries ? "\(request.item.title) · T\(request.season) E\(request.episode)" : request.item.title
    }

    // MARK: Estados

    private var phaseOverlay: some View {
        VStack(spacing: 16) {
            switch model.phase {
            case .resolving(let message):
                ProgressView().tint(.plixPrimary).scaleEffect(1.4)
                Text(message).font(.subheadline).foregroundColor(.white).multilineTextAlignment(.center)
                if let server = model.server {
                    Text("Servidor \(model.currentIndex + 1) de \(model.request.servers.count) · \(server.name)")
                        .font(.caption).foregroundColor(.plixMuted)
                }
                HStack(spacing: 12) {
                    if capture.isCapturing && !capture.needsUserInteraction {
                        Button("Ver servidor") { model.revealCapture() }.buttonStyle(PlixButtonStyle(filled: false))
                    }
                    Button("Siguiente servidor") { model.selectServer(model.currentIndex + 1) }
                        .buttonStyle(PlixButtonStyle(filled: false))
                        .disabled(model.currentIndex + 1 >= model.request.servers.count)
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.orange)
                Text(message).font(.subheadline).foregroundColor(.white).multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Reintentar") { model.retry() }.buttonStyle(PlixButtonStyle())
                    Button("Elegir servidor") { showServers = true }.buttonStyle(PlixButtonStyle(filled: false))
                }
            case .playing:
                EmptyView()
            }
            Button("Volver a los servidores") { close() }
                .font(.footnote).foregroundColor(.plixMuted).padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: 460)
    }

    private var captureOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verificación \(model.server?.name ?? "")").font(.headline).foregroundColor(.white)
                    Text("Completa el captcha y pulsa Play en el video").font(.caption).foregroundColor(.plixMuted)
                }
                Spacer()
                Button("Recargar verificación") { model.retry() }.font(.footnote)
                Button {
                    model.selectServer(model.currentIndex + 1)
                } label: {
                    Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Siguiente servidor")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.plixBackgroundDeep)
            CaptureWebView(webView: capture.webView)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func banner(_ text: String) -> some View {
        VStack {
            Text(text).font(.footnote.weight(.semibold)).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.black.opacity(0.75), in: Capsule())
                .padding(.top, 12)
            Spacer()
        }
    }

    // MARK: Controles

    private var controls: some View {
        ZStack {
            if model.locked {
                VStack {
                    HStack {
                        Spacer()
                        Button { model.locked = false; scheduleHide() } label: {
                            Image(systemName: "lock.fill").font(.title2).frame(width: 52, height: 52)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                        .accessibilityLabel("Desbloquear controles")
                    }
                    Spacer()
                }
                .padding(20)
            } else {
                LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                VStack {
                    topBar
                    Spacer()
                    centerButtons
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                HStack {
                    brightnessSlider
                    Spacer()
                }
                .padding(.leading, 4)
            }
        }
        .foregroundColor(.white)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { close() } label: { Image(systemName: "chevron.backward").font(.title3).frame(width: 44, height: 44) }
                .accessibilityLabel("Volver")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                if let server = model.server { Text(server.name).font(.caption).foregroundColor(.plixMuted) }
            }
            Spacer()
            if let room = watchParty.room, model.request.watchParty {
                Text("Sala \(room.roomCode)").font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.plixPrimary.opacity(0.85), in: Capsule())
                    .foregroundColor(.black)
                Button { showChat = true; watchParty.chatVisible = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left.and.bubble.right.fill").frame(width: 44, height: 44)
                        if watchParty.unreadCount > 0 {
                            Text("\(watchParty.unreadCount)").font(.caption2.bold()).padding(4)
                                .background(Color.red, in: Circle())
                        }
                    }
                }
                .accessibilityLabel("Abrir chat")
            }
            if model.canControl {
                Button { showServers = true } label: { Image(systemName: "server.rack").frame(width: 44, height: 44) }
                    .accessibilityLabel("Servidor")
            }
            if model.request.isSeries && model.canControl {
                Button { showEpisodes = true } label: { Image(systemName: "list.bullet.rectangle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Episodios")
            }
            AirPlayButton().frame(width: 44, height: 44)
            Button { showSettings = true } label: { Image(systemName: "gearshape.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("Calidad, audio y subtítulos")
            Button { model.locked = true } label: { Image(systemName: "lock.open.fill").frame(width: 44, height: 44) }
                .accessibilityLabel("Bloquear controles")
        }
    }

    private var centerButtons: some View {
        HStack(spacing: 56) {
            if model.canControl {
                Button { model.skip(-10); scheduleHide() } label: { Image(systemName: "gobackward.10").font(.system(size: 34)) }
                    .accessibilityLabel("Retroceder 10 segundos")
            }
            if model.buffering {
                ProgressView().tint(.white).scaleEffect(1.6).frame(width: 64, height: 64)
            } else if model.canControl {
                Button { model.togglePlay(); scheduleHide() } label: {
                    Image(systemName: model.isPlayingState ? "pause.fill" : "play.fill").font(.system(size: 50))
                        .frame(width: 64, height: 64)
                }
                .accessibilityLabel("Reproducir o pausar")
            }
            if model.canControl {
                Button { model.skip(10); scheduleHide() } label: { Image(systemName: "goforward.10").font(.system(size: 34)) }
                    .accessibilityLabel("Avanzar 10 segundos")
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if model.request.watchParty && !model.canControl {
                Text("Modo espectador · el anfitrión controla la reproducción.")
                    .font(.caption).foregroundColor(.plixMuted)
            }
            HStack(spacing: 12) {
                Text(TextUtil.formatDuration(ms: Int64((scrubbing ?? model.position) * 1000))).font(.caption.monospacedDigit())
                Slider(value: Binding(get: { scrubbing ?? model.position },
                                      set: { scrubbing = $0 }),
                       in: 0...max(1, model.duration)) { editing in
                    if !editing, let target = scrubbing {
                        model.scrub(to: target)
                        scrubbing = nil
                        scheduleHide()
                    } else {
                        hideTask?.cancel()
                    }
                }
                .disabled(!model.canControl || model.duration <= 0)
                Text(TextUtil.formatDuration(ms: Int64(model.duration * 1000))).font(.caption.monospacedDigit())
            }
            if let next = model.nextEpisode, model.canControl,
               model.reachedEnd || (model.duration > 0 && model.duration - model.position < 120) {
                HStack {
                    Spacer()
                    Button { model.playEpisode(next) } label: {
                        Label("Siguiente episodio", systemImage: "forward.end.fill")
                    }
                    .buttonStyle(PlixButtonStyle())
                }
            }
        }
    }

    private var brightnessSlider: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.max.fill").font(.caption)
            Slider(value: Binding(get: { model.brightness }, set: { model.setBrightness($0) }), in: 0.05...1)
                .frame(width: 130)
                .rotationEffect(.degrees(-90))
                .frame(width: 30, height: 130)
                .accessibilityLabel("Brillo")
        }
    }

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.2)) { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, model.isPlayingState, scrubbing == nil else { return }
            withAnimation(.easeOut(duration: 0.3)) { controlsVisible = false }
        }
    }

    private func close() {
        router.playback = nil
        dismiss()
    }
}

// MARK: Hojas del reproductor

struct PlayerSettingsSheet: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    private let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        NavigationStack {
            List {
                Section("Calidad de video") {
                    if model.qualities.isEmpty {
                        Text("Este servidor no ofrece calidades alternativas.").foregroundColor(.plixMuted)
                    }
                    ForEach(model.qualities) { option in
                        Button { model.selectQuality(option) } label: {
                            row(option.label == "Auto" ? "Automática" : option.label, selected: model.selectedQuality == option.label)
                        }
                    }
                }
                Section("Audio") {
                    if model.audioOptions.isEmpty {
                        Text("Este servidor no ofrece pistas alternativas.").foregroundColor(.plixMuted)
                    }
                    ForEach(Array(model.audioOptions.enumerated()), id: \.offset) { index, option in
                        Button { model.selectAudio(option) } label: {
                            row(option.displayName.isEmpty ? "Pista \(index + 1)" : option.displayName, selected: model.selectedAudio == option)
                        }
                    }
                }
                Section("Subtítulos") {
                    Button { model.selectSubtitle(nil) } label: { row("Desactivados", selected: model.selectedSubtitle == nil) }
                    ForEach(Array(model.subtitleOptions.enumerated()), id: \.offset) { index, option in
                        Button { model.selectSubtitle(option) } label: {
                            row(option.displayName.isEmpty ? "Pista \(index + 1)" : option.displayName, selected: model.selectedSubtitle == option)
                        }
                    }
                }
                if model.canControl {
                    Section("Velocidad") {
                        ForEach(speeds, id: \.self) { value in
                            Button { model.setSpeed(value) } label: {
                                row(value == 1 ? "Normal" : String(format: "%gx", value), selected: model.speed == value)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Audio y subtítulos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
    }

    private func row(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundColor(.plixText)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundColor(.plixPrimary) }
        }
    }
}

struct PlayerEpisodesSheet: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.episodes) { episode in
                Button {
                    dismiss()
                    model.playEpisode(episode)
                } label: {
                    HStack {
                        Text("T\(episode.season) - E\(episode.episode)").font(.caption.bold()).foregroundColor(.plixPrimary)
                        Text(episode.name).foregroundColor(.plixText).lineLimit(1)
                        Spacer()
                        if episode.episode == model.request.episode {
                            Text("Reproduciendo").font(.caption).foregroundColor(.plixAccent)
                        } else if PlaybackProgressStore.watchedEpisodes(model.request.item.id, episode.season).contains(episode.episode) {
                            Text("Visto").font(.caption).foregroundColor(.plixMuted)
                        }
                    }
                }
            }
            .navigationTitle("Episodios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}

struct PlayerServersSheet: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(model.request.servers.enumerated()), id: \.element.id) { index, server in
                Button {
                    dismiss()
                    model.selectServer(index)
                } label: {
                    HStack {
                        Text("\(index + 1).").foregroundColor(.plixMuted)
                        VStack(alignment: .leading) {
                            Text(server.name).foregroundColor(.plixText)
                            Text(LanguageGroup.of(server).label).font(.caption).foregroundColor(.plixMuted)
                        }
                        Spacer()
                        if index == model.currentIndex { Text("actual").font(.caption).foregroundColor(.plixAccent) }
                    }
                }
            }
            .overlay { if model.request.servers.isEmpty { Text("No hay servidores en la cola").foregroundColor(.plixMuted) } }
            .navigationTitle("Cambiar servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}
