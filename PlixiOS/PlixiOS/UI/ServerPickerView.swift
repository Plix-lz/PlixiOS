import SwiftUI

@MainActor
final class ServerPickerModel: ObservableObject {
    @Published private(set) var servers: [StreamServer] = []
    @Published private(set) var complete = false
    @Published var language: LanguageGroup = .latino
    @Published private(set) var status = ""
    @Published private(set) var busy = false
    @Published var error: String?
    private var userPickedLanguage = false
    private var tasks: [Task<Void, Never>] = []
    let context: ServerPickerContext

    init(context: ServerPickerContext) { self.context = context }

    func grouped(_ group: LanguageGroup) -> [StreamServer] {
        ServerChain.sortForPlayback(servers).filter { LanguageGroup.of($0) == group }
    }

    func chooseLanguage(_ group: LanguageGroup) {
        language = group
        userPickedLanguage = true
    }

    func start(router: AppRouter) {
        guard tasks.isEmpty else { return }
        let item = context.item
        let isSeries = item.mediaType == .tv
        tasks.append(Task {
            await StreamLinkRepository.shared.fetchProgressive(contentId: item.id, isSeries: isSeries,
                                                               season: context.season, episode: context.episode) { [weak self] list, done in
                guard let self else { return }
                self.servers = list
                self.complete = done
                if done && !self.userPickedLanguage && self.grouped(self.language).isEmpty,
                   let first = LanguageGroup.allCases.first(where: { !self.grouped($0).isEmpty }) {
                    self.language = first
                }
                if done && self.context.watchPartyGuest { self.autoFollowHost(router: router) }
            }
        })
        guard !context.watchPartyGuest else {
            status = "Buscando el servidor del anfitrión…"
            return
        }
        status = "Buscando enlace directo…"
        tasks.append(Task {
            let resolved = await PelixplayHLSResolver.resolve(contentId: item.id, season: isSeries ? context.season : -1,
                                                               episode: isSeries ? context.episode : -1)
            guard !Task.isCancelled else { return }
            if let resolved {
                let (server, stream) = resolved
                status = "Enlace directo encontrado (\(server.name)). Abriendo…"
                let queue = buildQueue(chosen: server)
                router.startPlayback(PlaybackRequest(item: item, season: context.season, episode: context.episode,
                                                     servers: queue, preResolved: stream, watchParty: false))
            } else {
                status = "Sin enlace directo. Elige un servidor de la lista."
            }
        })
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Elegido primero, luego el mismo idioma, luego el resto (como la cola de Android).
    func buildQueue(chosen: StreamServer) -> [StreamServer] {
        let sorted = ServerChain.sortForPlayback(servers).filter { $0.id != chosen.id }
        let group = LanguageGroup.of(chosen)
        return [chosen] + sorted.filter { LanguageGroup.of($0) == group } + sorted.filter { LanguageGroup.of($0) != group }
    }

    func pick(_ server: StreamServer, watchParty: Bool, router: AppRouter) {
        cancel()
        let item = context.item
        let queue = buildQueue(chosen: server)
        guard watchParty else {
            router.startPlayback(PlaybackRequest(item: item, season: context.season, episode: context.episode,
                                                 servers: queue, preResolved: nil, watchParty: false))
            return
        }
        busy = true
        Task {
            do {
                let session = WatchPartySession.shared
                if !session.isActive || !session.isHost { _ = try await session.createRoom() }
                try await session.setContent(item: item, season: context.season, episode: context.episode, server: server)
                busy = false
                router.startPlayback(PlaybackRequest(item: item, season: context.season, episode: context.episode,
                                                     servers: queue, preResolved: nil, watchParty: true))
            } catch {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }

    private func autoFollowHost(router: AppRouter) {
        guard let room = WatchPartySession.shared.room else { return }
        if let index = WatchPartyServerMatcher.indexOf(servers, name: room.preferredServerName,
                                                       language: room.preferredServerLanguage, url: room.preferredServerUrl) {
            let chosen = servers[index]
            status = "Mismo servidor que el anfitrión: \(chosen.name)"
            pickAsGuest(chosen, router: router)
        } else {
            status = "No encontramos el servidor del anfitrión. Elegí uno similar."
        }
    }

    func pickAsGuest(_ server: StreamServer, router: AppRouter) {
        cancel()
        router.startPlayback(PlaybackRequest(item: context.item, season: context.season, episode: context.episode,
                                             servers: buildQueue(chosen: server), preResolved: nil, watchParty: true))
    }
}

struct ServerPickerView: View {
    @StateObject private var model: ServerPickerModel
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var watchParty: WatchPartySession
    @Environment(\.dismiss) private var dismiss
    @State private var watchPartyMode = false

    init(context: ServerPickerContext) {
        _model = StateObject(wrappedValue: ServerPickerModel(context: context))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.context.item.title).font(.title3.bold()).foregroundColor(.plixText)
                    if model.context.item.mediaType == .tv {
                        Text("Temporada \(model.context.season) · Episodio \(model.context.episode)")
                            .font(.subheadline).foregroundColor(.plixMuted)
                    }
                    if !model.status.isEmpty {
                        Text(model.status).font(.footnote).foregroundColor(.plixAccent)
                    }
                }
                .padding(.horizontal, 16)

                if !model.context.watchPartyGuest && account.isSignedIn && account.cloudAvailable {
                    Toggle(isOn: $watchPartyMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ver en Cine Virtual").font(.subheadline.weight(.semibold))
                            Text(watchParty.isHost ? "Sala \(watchParty.room?.roomCode ?? "")" : "Se creará una sala al elegir un servidor.")
                                .font(.caption).foregroundColor(.plixMuted)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Text("Seleccionar idioma").font(.caption.weight(.bold)).foregroundColor(.plixMuted).padding(.horizontal, 16)
                HStack(spacing: 10) {
                    ForEach(LanguageGroup.allCases) { group in
                        let count = model.grouped(group).count
                        Button { model.chooseLanguage(group) } label: {
                            VStack(spacing: 6) {
                                BundleImage(name: group.flagImage, contentMode: .fill)
                                    .frame(width: 44, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(group.label).font(.caption.weight(.semibold))
                                Text("\(count)").font(.caption2).foregroundColor(.plixMuted)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(model.language == group ? Color.plixPrimary.opacity(0.22) : Color.plixSurface,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(model.language == group ? Color.plixPrimary : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.plixText)
                    }
                }
                .padding(.horizontal, 16)

                let list = model.grouped(model.language)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if list.isEmpty {
                            if model.complete {
                                Text(model.servers.isEmpty ? "No encontramos enlaces para este título." : "No hay servidores en \(model.language.label).")
                                    .font(.footnote).foregroundColor(.plixMuted).padding(.top, 30)
                            } else {
                                LoadingView(message: "Buscando servidores…")
                            }
                        }
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, server in
                            Button {
                                if model.context.watchPartyGuest {
                                    model.pickAsGuest(server, router: router)
                                } else {
                                    model.pick(server, watchParty: watchPartyMode, router: router)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.bold()).frame(width: 28, height: 28)
                                        .background(Color.plixSurfaceLight, in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name).font(.subheadline.weight(.semibold)).foregroundColor(.plixText)
                                        Text(server.directStream ? "Directo" : StreamURL.host(server.url))
                                            .font(.caption2).foregroundColor(.plixMuted).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "play.fill").foregroundColor(.plixPrimary)
                                }
                                .padding(12)
                                .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.busy)
                        }
                        if model.complete && !model.servers.isEmpty {
                            Text(model.servers.count == 1 ? "1 enlace disponible" : "\(model.servers.count) enlaces disponibles")
                                .font(.caption).foregroundColor(.plixMuted).padding(.top, 6)
                        } else if !model.complete && !list.isEmpty {
                            ProgressView().tint(.plixPrimary).padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .padding(.top, 8)
            .background(Color.plixBackground.ignoresSafeArea())
            .navigationTitle("Elige un servidor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { model.cancel(); dismiss() }
                }
            }
            .overlay { if model.busy { LoadingView(message: "Creando sala…").background(Color.black.opacity(0.6)) } }
            .alert("Cine Virtual", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
        }
        .onAppear {
            watchPartyMode = watchParty.isHost
            model.start(router: router)
        }
        .onDisappear { model.cancel() }
    }
}
