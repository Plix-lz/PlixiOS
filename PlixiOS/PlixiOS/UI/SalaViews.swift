import SwiftUI
import UIKit

struct SignInRequiredView: View {
    let message: String
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        MessageView(icon: "person.crop.circle.badge.exclamationmark", message: message, actionTitle: "Iniciar sesión") {
            router.select(.account)
        }
    }
}

struct SalaVirtualView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var watchParty: WatchPartySession
    @State private var friends: [FriendCard] = []
    @State private var loadingFriends = false
    @State private var showJoin = false
    @State private var joinCode = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.isSignedIn ? "¡Hola! \(account.username)" : "¡Hola!").font(.title2.bold()).foregroundColor(.plixText)
                    Text("¿Qué contenido compartirás con tus amigos ahora?").font(.subheadline).foregroundColor(.plixMuted)
                }
                .padding(.horizontal, 16)

                BundleImage(name: "cine_virtual_share.jpg", contentMode: .fill)
                    .frame(height: 150).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)

                if !account.cloudAvailable {
                    MessageView(icon: "icloud.slash", message: "Cine Virtual y amigos necesitan Firebase. Esta compilación no incluye GoogleService-Info.plist.")
                } else if !account.isSignedIn {
                    SignInRequiredView(message: "Inicia sesión para usar Sala Virtual, amigos y Cine Virtual.")
                } else {
                    myIdCard
                    options
                    friendsSection
                }
                recents
            }
            .padding(.vertical, 12)
        }
        .task { await loadFriends() }
        .refreshable { await loadFriends() }
        .alert("Unirse al Cine Virtual", isPresented: $showJoin) {
            TextField("XXXX", text: $joinCode).textInputAutocapitalization(.characters)
            Button("Unirse a la sala") { join() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Ingresá el código que te compartió el anfitrión.")
        }
        .alert("Cine Virtual", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(error ?? "") }
        .overlay { if busy { LoadingView(message: "Uniéndose…").background(Color.black.opacity(0.6)) } }
    }

    private var myIdCard: some View {
        Button {
            UIPasteboard.general.string = account.plixUserIdLabel
            router.showToast("ID copiado")
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.plixUserId > 0 ? "MI ID: \(account.plixUserIdLabel)" : "MI ID: —").font(.headline)
                    Text("Tocar para copiar").font(.caption).foregroundColor(.plixMuted)
                }
                Spacer()
                Image(systemName: "doc.on.doc")
            }
            .foregroundColor(.plixText)
            .padding(14)
            .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var options: some View {
        VStack(spacing: 10) {
            if watchParty.isActive {
                optionRow(icon: "play.tv.fill", title: "Cine Virtual · Sala \(watchParty.room?.roomCode ?? "")",
                          subtitle: watchParty.isHost ? "Sos el anfitrión" : "Estás en la sala") { router.open(.watchRoom) }
            } else {
                optionRow(icon: "plus.circle.fill", title: "Crear sala", subtitle: "Mirá la misma película o episodio en sincronía con tus amigos.") {
                    createRoom()
                }
            }
            optionRow(icon: "ticket.fill", title: "Unirse a sala", subtitle: "Ingresá el código de una sala de cine virtual") {
                joinCode = ""
                showJoin = true
            }
            optionRow(icon: "person.badge.plus", title: "Solicitudes", subtitle: "Ver y responder solicitudes de amistad",
                      badge: account.incomingRequests.count) { router.open(.friendRequests) }
            optionRow(icon: "magnifyingglass", title: "Buscar amigos", subtitle: "Buscá usuarios por su ID PLIX") { router.open(.findFriends) }
        }
        .padding(.horizontal, 16)
    }

    private func optionRow(icon: String, title: String, subtitle: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundColor(.plixPrimary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.plixText)
                    Text(subtitle).font(.caption).foregroundColor(.plixMuted).lineLimit(2)
                }
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red, in: Capsule()).foregroundColor(.white)
                }
                Image(systemName: "chevron.right").foregroundColor(.plixMuted)
            }
            .padding(14)
            .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Amigos").font(.headline).foregroundColor(.plixText)
            if loadingFriends && friends.isEmpty {
                ProgressView().tint(.plixPrimary)
            } else if friends.isEmpty {
                Text("Sin amigos.").font(.footnote).foregroundColor(.plixMuted)
            } else {
                ForEach(friends) { friend in
                    Button { router.open(.publicProfile(friend.uid)) } label: {
                        HStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(ref: friend.avatar, size: 46)
                                Circle().fill(friend.online ? Color.green : Color.gray).frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.plixBackground, lineWidth: 2))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.username).font(.subheadline.weight(.semibold)).foregroundColor(.plixText)
                                Text(friend.online ? "Online" : (friend.lastSeenMs > 0 ? TextUtil.relativeLastSeen(friend.lastSeenMs) : "Sin conexión reciente"))
                                    .font(.caption).foregroundColor(friend.online ? .green : .plixMuted)
                            }
                            Spacer()
                            Text(friend.plixUserIdLabel).font(.caption2).foregroundColor(.plixMuted)
                        }
                        .padding(10)
                        .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var recents: some View {
        let items = ContentEntriesStore.salaVirtual.list()
        return VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("Recientes").font(.headline).foregroundColor(.plixText).padding(.horizontal, 16)
                Text("Todavía no hay títulos vistos en sala").font(.footnote).foregroundColor(.plixMuted).padding(.horizontal, 16)
            } else {
                MediaRow(title: "Recientes", items: items) { router.openDetail($0) }
            }
        }
    }

    private func loadFriends() async {
        guard account.isSignedIn, account.cloudAvailable else { return }
        loadingFriends = true
        friends = (try? await FriendsService.listFriends()) ?? friends
        loadingFriends = false
    }

    private func createRoom() {
        busy = true
        Task {
            do {
                _ = try await watchParty.createRoom()
                busy = false
                router.open(.watchRoom)
            } catch {
                busy = false
                self.error = error.localizedDescription
            }
        }
    }

    private func join() {
        let code = joinCode
        busy = true
        Task {
            do {
                try await watchParty.join(code: code)
                busy = false
                router.open(.watchRoom)
            } catch {
                busy = false
                self.error = (error as? PlixError).map { $0.localizedDescription } ?? "No se pudo conectar al Cine Virtual."
            }
        }
    }
}

// MARK: Sala de Cine Virtual

struct WatchRoomView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var watchParty: WatchPartySession
    @Environment(\.dismiss) private var dismiss
    @State private var lastFollowedSeq: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if let room = watchParty.room {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sala \(room.roomCode)").font(.title2.bold()).foregroundColor(.plixText)
                            Text(watchParty.isHost ? "Sos el anfitrión" : "Anfitrión: \(room.hostName)")
                                .font(.caption).foregroundColor(.plixMuted)
                        }
                        Spacer()
                        ShareLink(item: "Únete a mi Cine Virtual en Plix - LzPlay con el código\n\n*\(room.roomCode)*") {
                            Label("Compartir código", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PlixButtonStyle(filled: false))
                    }
                    Text(statusText(room)).font(.footnote).foregroundColor(.plixAccent)
                    if room.hasContent {
                        HStack(spacing: 12) {
                            RemoteImage(room.posterUrl).frame(width: 60, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("“\(room.contentTitle)”").font(.headline).foregroundColor(.plixText)
                                if room.isSeries { Text("T\(room.season) E\(room.episode)").font(.caption).foregroundColor(.plixMuted) }
                                if !room.preferredServerName.isEmpty {
                                    Text("Servidor: \(room.preferredServerName)").font(.caption).foregroundColor(.plixMuted)
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        if watchParty.isHost {
                            Button(room.hasContent ? "Continuar con este título" : "Elegir película o serie") {
                                if room.hasContent {
                                    router.serverPicker = ServerPickerContext(item: room.mediaItem, season: room.season, episode: room.episode, watchPartyGuest: false)
                                } else {
                                    router.select(.home)
                                    router.showToast("Elegí un título y activá \"Ver en Cine Virtual\" al elegir servidor")
                                }
                            }
                            .buttonStyle(PlixButtonStyle())
                        } else if room.isReadyForGuests {
                            Button("Unirse a la reproducción") { followHost(room) }.buttonStyle(PlixButtonStyle())
                        }
                        Button("Salir", role: .destructive) {
                            Task { await watchParty.leave() }
                            dismiss()
                        }
                        .buttonStyle(PlixButtonStyle(filled: false))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(watchParty.participants) { participant in
                                Text(participant.displayName + (participant.uid == room.hostId ? " ★" : ""))
                                    .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.plixSurfaceLight, in: Capsule())
                            }
                        }
                    }
                    Text(watchParty.participants.count == 1 ? "1 activo" : "\(watchParty.participants.count) activos")
                        .font(.caption2).foregroundColor(.plixMuted)
                }
                .padding(16)
                Divider()
                WatchPartyChatView(embedded: true)
            } else {
                MessageView(icon: "tv.slash", message: watchParty.lastError ?? "Sala no disponible. El anfitrión cerró la sala.")
            }
        }
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle("Cine Virtual")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: watchParty.room?.seq) { _ in autoFollow() }
        .onAppear { watchParty.chatVisible = true; autoFollow() }
        .onDisappear { watchParty.chatVisible = false }
    }

    private func statusText(_ room: WatchPartyRoom) -> String {
        if watchParty.isHost {
            return room.hasContent ? "Compartí este código con tus amigos para que se unan." : "Elegí un título para transmitir en Cine Virtual."
        }
        if !room.hasContent { return "Esperando a que el anfitrión elija el contenido…" }
        if !room.hasPreferredServer { return "Contenido listo. Esperando a que el anfitrión elija el servidor…" }
        return room.isPlaying ? "El anfitrión ya está reproduciendo. Entrando…" : "Sala lista"
    }

    /// El invitado entra solo al reproductor cuando el anfitrión ya eligió contenido y servidor.
    private func autoFollow() {
        guard let room = watchParty.room, !watchParty.isHost, room.isReadyForGuests, router.playback == nil,
              router.serverPicker == nil else { return }
        let key = "\(room.contentId):\(room.season):\(room.episode):\(room.preferredServerUrl)"
        guard key != lastFollowedSeq else { return }
        lastFollowedSeq = key
        followHost(room)
    }

    private func followHost(_ room: WatchPartyRoom) {
        router.serverPicker = ServerPickerContext(item: room.mediaItem, season: room.season, episode: room.episode, watchPartyGuest: true)
    }
}

struct WatchPartyChatView: View {
    var embedded = false
    @EnvironmentObject private var watchParty: WatchPartySession
    @StateObject private var recorder = VoiceNoteRecorder()
    @ObservedObject private var voicePlayer = VoiceNotePlayer.shared
    @State private var text = ""
    @State private var showStickers = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                HStack {
                    Text("Chat de la sala").font(.headline)
                    Spacer()
                    Text(watchParty.participants.count == 1 ? "1 activo" : "\(watchParty.participants.count) activos")
                        .font(.caption).foregroundColor(.plixMuted)
                }
                .padding()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(watchParty.messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: watchParty.messages.count) { _ in
                    if let last = watchParty.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if let error { Text(error).font(.caption).foregroundColor(.orange).padding(.horizontal) }
            if showStickers { stickerTray }
            inputBar
        }
        .background(Color.plixBackground)
        .onAppear { watchParty.chatVisible = true }
        .onDisappear { if !embedded { watchParty.chatVisible = false } }
        .onChange(of: recorder.limitReached) { reached in if reached { finishRecording(send: true) } }
    }

    @ViewBuilder
    private func bubble(_ message: WatchPartyMessage) -> some View {
        let mine = message.uid == watchParty.uid
        if message.isSystem {
            Text(message.text).font(.caption).foregroundColor(.plixMuted).frame(maxWidth: .infinity)
        } else {
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine { Text(message.displayName).font(.caption2.bold()).foregroundColor(.plixAccent) }
                Group {
                    if message.isSticker {
                        RemoteImage(url: StickerCatalog.url(for: message.text), contentMode: .fit).frame(width: 110, height: 110)
                    } else if message.isVoice {
                        Button { voicePlayer.toggle(message) } label: {
                            Label("\(message.voiceDurationMs / 1000) s",
                                  systemImage: voicePlayer.playingId == message.id ? "stop.fill" : "play.fill")
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(mine ? Color.plixPrimary : Color.plixSurfaceLight, in: Capsule())
                                .foregroundColor(mine ? .black : .plixText)
                        }
                    } else {
                        Text(message.text).font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(mine ? Color.plixPrimary : Color.plixSurfaceLight, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundColor(mine ? .black : .plixText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    private var stickerTray: some View {
        let stickers = StickerStore.selected
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if stickers.isEmpty {
                    Text("No tenés stickers. Elegilos en Cuenta.").font(.caption).foregroundColor(.plixMuted)
                }
                ForEach(stickers, id: \.self) { key in
                    Button { send { try await watchParty.sendSticker(key) }; showStickers = false } label: {
                        RemoteImage(url: StickerCatalog.url(for: key), contentMode: .fit).frame(width: 64, height: 64)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 76)
        .background(Color.plixSurface)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { showStickers.toggle() } label: { Image(systemName: "face.smiling").font(.title3).frame(width: 40, height: 40) }
                .accessibilityLabel("Stickers")
            if recorder.isRecording {
                Text("Grabando… \(Int(recorder.elapsed)) s (máx. 30 s)").font(.footnote).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { finishRecording(send: false) } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                    .accessibilityLabel("Cancelar nota de voz")
                Button { finishRecording(send: true) } label: { Image(systemName: "paperplane.fill").frame(width: 40, height: 40) }
                    .accessibilityLabel("Enviar nota de voz")
            } else {
                TextField("Escribí un mensaje…", text: $text)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Color.plixSurface, in: Capsule())
                    .submitLabel(.send)
                    .onSubmit(sendText)
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task {
                            do { try await recorder.start(); error = nil } catch { self.error = error.localizedDescription }
                        }
                    } label: { Image(systemName: "mic.fill").frame(width: 40, height: 40) }
                    .accessibilityLabel("Grabar nota de voz (máx. 30 s)")
                } else {
                    Button(action: sendText) { Image(systemName: "paperplane.fill").frame(width: 40, height: 40) }
                        .accessibilityLabel("Enviar")
                }
            }
        }
        .foregroundColor(.plixPrimary)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.plixBackgroundDeep)
    }

    private func sendText() {
        let value = text
        text = ""
        send { try await watchParty.sendText(value) }
    }

    private func finishRecording(send shouldSend: Bool) {
        guard let note = recorder.stop(send: shouldSend) else { return }
        send { try await watchParty.sendVoice(note.0, durationMs: note.1) }
    }

    private func send(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); error = nil } catch { self.error = "No se pudo enviar el mensaje" }
        }
    }
}

// MARK: Amigos

struct FindFriendsView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var query = ""
    @State private var result: PublicProfile?
    @State private var message = "Buscá un usuario por su ID para ver su perfil"
    @State private var searching = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Pegá o escribí un ID (#00000001)", text: $query)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit(search)
                Button("Buscar", action: search).buttonStyle(PlixButtonStyle())
            }
            if searching {
                LoadingView(message: "Buscando…")
            } else if let result {
                Button { router.open(.publicProfile(result.uid)) } label: { ProfileCard(profile: result) }
                    .buttonStyle(.plain)
            } else {
                Text(message).font(.footnote).foregroundColor(.plixMuted)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle("Buscar amigos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() {
        guard SessionStore.isSignedIn else { message = "Iniciá sesión para buscar amigos"; return }
        guard SyncConfig.parsePlixUserId(query) > 0 else { message = "Ingresá un ID válido, por ejemplo #00000001"; result = nil; return }
        searching = true
        Task {
            do {
                result = try await PublicProfileService.find(plixUserId: query)
                if result == nil { message = "No se encontró ningún usuario con ese ID" }
            } catch {
                result = nil
                message = "No se pudo buscar. Revisá tu conexión"
            }
            searching = false
        }
    }
}

struct ProfileCard: View {
    let profile: PublicProfile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(ref: profile.icon, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.username).font(.headline).foregroundColor(.plixText)
                Text(profile.plixUserIdLabel).font(.caption).foregroundColor(.plixMuted)
                Text("Ver información del usuario").font(.caption).foregroundColor(.plixAccent)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.plixMuted)
        }
        .padding(12)
        .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct FriendRequestsView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var router: AppRouter
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundColor(.orange) }
            if account.incomingRequests.isEmpty && !loading {
                Text("Todavía no hay solicitudes").foregroundColor(.plixMuted)
            }
            ForEach(account.incomingRequests) { request in
                HStack(spacing: 12) {
                    AvatarView(ref: request.fromAvatar, size: 44)
                    VStack(alignment: .leading) {
                        Text(request.fromUsername).font(.subheadline.weight(.semibold))
                        Text(request.fromPlixUserIdLabel).font(.caption).foregroundColor(.plixMuted)
                    }
                    Spacer()
                    Button { act(request, accept: true) } label: { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundColor(.green) }
                        .buttonStyle(.borderless).accessibilityLabel("Aceptar solicitud")
                    Button { act(request, accept: false) } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red) }
                        .buttonStyle(.borderless).accessibilityLabel("Rechazar solicitud")
                }
                .listRowBackground(Color.plixSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle("Solicitudes")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if loading { ProgressView().tint(.plixPrimary) } }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        loading = true
        do {
            account.refreshIncoming(try await FriendsService.listIncoming())
            error = nil
        } catch {
            self.error = "No se pudieron cargar las solicitudes"
        }
        loading = false
    }

    private func act(_ request: FriendRequest, accept: Bool) {
        Task {
            do {
                if accept { try await FriendsService.accept(request) } else { try await FriendsService.reject(request) }
                router.showToast(accept ? "Solicitud aceptada" : "Solicitud rechazada")
                await refresh()
                if accept { await PublicProfileService.publishQuietly() }
            } catch {
                self.error = "No se pudo completar la acción"
            }
        }
    }
}

struct PublicProfileView: View {
    let uid: String
    @EnvironmentObject private var router: AppRouter
    @State private var profile: PublicProfile?
    @State private var failed = false
    @State private var isFriend = false
    @State private var sending = false

    var body: some View {
        ScrollView {
            if let profile {
                VStack(spacing: 16) {
                    ZStack(alignment: .bottomLeading) {
                        ProfileBackdropView(ref: profile.backdrop).frame(height: 180).clipped()
                        HStack(alignment: .bottom, spacing: 12) {
                            AvatarView(ref: profile.icon, size: 84)
                            VStack(alignment: .leading) {
                                Text(profile.username).font(.title3.bold()).foregroundColor(.white)
                                Text("ID \(profile.plixUserIdLabel)").font(.caption).foregroundColor(.plixText)
                            }
                        }
                        .padding(16)
                        .offset(y: 30)
                    }
                    .padding(.bottom, 30)
                    Text(profile.bio.isEmpty ? "¡Hola! Estoy viendo películas y series en PLIX 🍿" : profile.bio)
                        .font(.subheadline).foregroundColor(.plixMuted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
                    StatsGrid(stats: profile.stats, friends: profile.friendsCount)
                    if profile.uid != SessionStore.uid && !isFriend {
                        Button(sending ? "Enviando…" : "Enviar solicitud") { sendRequest(profile) }
                            .buttonStyle(PlixButtonStyle())
                            .disabled(sending)
                    }
                }
            } else if failed {
                MessageView(icon: "person.fill.questionmark", message: "No se pudo cargar el perfil.")
            } else {
                LoadingView()
            }
        }
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            profile = try await PublicProfileService.fetch(uid: uid)
            failed = profile == nil
            if let db = CloudConfig.db, SessionStore.isSignedIn {
                isFriend = (try? await FriendsService.areFriends(db: db, SessionStore.uid, uid)) ?? false
            }
        } catch {
            failed = true
        }
    }

    private func sendRequest(_ profile: PublicProfile) {
        sending = true
        Task {
            do {
                try await FriendsService.sendRequest(to: profile)
                router.showToast("Solicitud enviada")
            } catch {
                router.showToast((error as? PlixError)?.localizedDescription ?? "No se pudo enviar la solicitud")
            }
            sending = false
        }
    }
}

struct StatsGrid: View {
    let stats: ProfileStats
    var friends: Int = -1

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            stat("Logros desbloqueados", "\(stats.achievements) Logros")
            stat("Películas reproducidas", "\(stats.movies)")
            stat("Series reproducidas", "\(stats.series)")
            stat("Episodios reproducidos", "\(stats.episodes)")
            stat("Tiempo total en la aplicación", stats.usageMs > 0 ? TextUtil.formatUsage(ms: stats.usageMs) : "0 min")
            if friends >= 0 { stat("Amigos", "\(friends)") }
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.headline).foregroundColor(.plixText)
            Text(title).font(.caption).foregroundColor(.plixMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
