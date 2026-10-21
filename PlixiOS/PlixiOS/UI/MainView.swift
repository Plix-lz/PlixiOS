import SwiftUI

struct MainView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var achievements: AchievementManager
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var account: AccountManager

    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack(path: $router.path) {
                VStack(spacing: 0) {
                    HeaderBar()
                    if !network.isOnline { OfflineBanner() }
                    ZStack {
                        Color.plixBackground.ignoresSafeArea()
                        if router.searchActive {
                            SearchView()
                        } else {
                            sectionContent
                        }
                    }
                }
                .background(Color.plixBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                        .toolbarBackground(Color.plixBackground, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
            }

            if router.drawerOpen {
                DrawerView()
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }

            VStack(spacing: 8) {
                if let first = achievements.toastQueue.first {
                    AchievementToastView(achievement: first, extra: achievements.toastQueue.count - 1)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { achievements.dismissToast() }
                        .task(id: first.id) {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            withAnimation { achievements.dismissToast() }
                        }
                }
                if let toast = router.toast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.plixSurfaceLight, in: Capsule())
                        .foregroundColor(.plixText)
                        .transition(.opacity)
                }
            }
            .padding(.top, 8)
            .animation(.spring(), value: achievements.toastQueue.first?.id)
            .zIndex(3)
        }
        .sheet(item: $router.serverPicker) { context in
            ServerPickerView(context: context)
                .presentationDetents([.large])
        }
        .fullScreenCover(item: $router.playback) { request in
            PlayerScreen(request: request)
        }
        .sheet(item: Binding(get: { router.trailerKey.map(TrailerKey.init) }, set: { router.trailerKey = $0?.id })) { key in
            TrailerView(videoKey: key.id)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch router.section {
        case .home: HomeView(kids: false)
        case .movies: HostCatalogView(type: .movie)
        case .series: HostCatalogView(type: .tv)
        case .kids: HomeView(kids: true)
        case .platforms: PlatformsView()
        case .myList: LibraryView(mode: .myList)
        case .sala: SalaVirtualView()
        case .history: LibraryView(mode: .history)
        case .achievements: AchievementsView()
        case .design: DesignView()
        case .account: AccountView()
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .detail(let item):
            if item.mediaType == .movie { MovieDetailView(item: item) } else { SeriesDetailView(item: item) }
        case .genre(let genre): GenreContentView(genre: genre)
        case .platform(let platform): PlatformContentView(platform: platform)
        case .publicProfile(let uid): PublicProfileView(uid: uid)
        case .findFriends: FindFriendsView()
        case .friendRequests: FriendRequestsView()
        case .watchRoom: WatchRoomView()
        }
    }
}

struct TrailerKey: Identifiable { let id: String }

struct HeaderBar: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var account: AccountManager
    @StateObject private var watcher = PrefsWatcher([ProfileImageStore.avatar.name])

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.easeOut(duration: 0.22)) { router.drawerOpen = true }
            } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Menú")

            Button { router.select(.home) } label: { BrandLogo() }
                .buttonStyle(.plain)

            Spacer()

            Button {
                router.searchActive.toggle()
            } label: {
                Image(systemName: router.searchActive ? "xmark" : "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(router.searchActive ? "Cerrar búsqueda" : "Buscar")

            Button { router.select(.account) } label: {
                ZStack(alignment: .topTrailing) {
                    AvatarView(ref: ProfileImageStore.avatar.current, size: 32).id(watcher.revision)
                    if !account.incomingRequests.isEmpty {
                        Circle().fill(Color.red).frame(width: 10, height: 10).offset(x: 3, y: -3)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Perfil")
        }
        .foregroundColor(.plixText)
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(Color.plixBackgroundDeep)
    }
}

struct DrawerView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var account: AccountManager

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { router.drawerOpen = false } }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BrandLogo(height: 30)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { router.drawerOpen = false }
                    } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Cerrar menú")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if account.isSignedIn {
                    Text(account.syncLabel)
                        .font(.caption)
                        .foregroundColor(.plixMuted)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(MainSection.allCases) { section in
                            Button { router.select(section) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: section.icon).frame(width: 24)
                                    Text(section.title).font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    if section == .sala && !account.incomingRequests.isEmpty {
                                        Text("\(account.incomingRequests.count)")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Color.red, in: Capsule())
                                    }
                                }
                                .foregroundColor(router.section == section ? .plixPrimary : .plixText)
                                .padding(.horizontal, 20)
                                .frame(height: 48)
                                .background(router.section == section ? Color.plixPrimary.opacity(0.12) : .clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text("Versión \(AppConfig.appVersion)")
                    .font(.caption2)
                    .foregroundColor(.plixMuted)
                    .padding(20)
            }
            .frame(width: 290)
            .frame(maxHeight: .infinity)
            .background(Color.plixBackgroundDeep.ignoresSafeArea())
        }
    }
}

extension AccountManager {
    var syncLabel: String {
        switch syncState {
        case .syncing: return "⟳ Sincronizando…"
        case .synced: return "✓ Sincronizado · \(username)"
        case .failed(let message): return message
        case .idle: return "Guardar datos · \(username)"
        }
    }
}
