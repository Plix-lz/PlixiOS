import SwiftUI

@MainActor
final class HomeModel: ObservableObject {
    struct LoadedRow: Identifiable {
        let section: HomeSection
        var items: [MediaItem]
        var id: String { section.id }
    }

    @Published private(set) var rows: [LoadedRow] = []
    @Published private(set) var genres: [GenreEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var heroLogos: [String: String] = [:]
    private var loadedOnce = false
    let kids: Bool

    init(kids: Bool) { self.kids = kids }

    var heroItems: [MediaItem] { Array((rows.first?.items ?? []).prefix(5)) }

    func loadIfNeeded() async {
        guard !loadedOnce else { return }
        await reload(refresh: false)
    }

    func reload(refresh: Bool) async {
        if refresh { await TMDBClient.shared.prepareHomeRefresh() }
        loadedOnce = true
        loading = true
        error = nil
        guard !AppConfig.tmdbApiKey.isEmpty else {
            error = PlixError.missingApiKey.localizedDescription
            loading = false
            return
        }
        let sections: [HomeSection]
        if kids { sections = await TMDBClient.shared.kidsSections() } else { sections = await TMDBClient.shared.homeSections() }
        let profile = GenreTasteStore.profile()
        var collected: [LoadedRow] = []
        rows = []
        await withTaskGroup(of: (Int, [MediaItem]).self) { group in
            for (index, section) in sections.enumerated() {
                group.addTask {
                    let items = (try? await TMDBClient.shared.loadSection(section, profile: profile)) ?? []
                    return (index, items)
                }
            }
            for await (index, items) in group where !items.isEmpty {
                collected.append(LoadedRow(section: sections[index], items: items))
                let order = Dictionary(uniqueKeysWithValues: sections.enumerated().map { ($0.element.id, $0.offset) })
                rows = collected.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            }
        }
        if !kids { genres = (try? await TMDBClient.shared.homeGenres()) ?? [] }
        loading = false
        if rows.isEmpty { error = NetworkMonitor.shared.isOnline ? "No se pudo cargar el contenido." : "Sin conexión. Conéctate para ver el catálogo." }
        for item in heroItems where heroLogos[item.key] == nil {
            heroLogos[item.key] = await TMDBClient.shared.heroLogo(item)
        }
    }
}

struct HomeView: View {
    let kids: Bool
    @StateObject private var model: HomeModel
    @EnvironmentObject private var router: AppRouter

    init(kids: Bool) {
        self.kids = kids
        _model = StateObject(wrappedValue: HomeModel(kids: kids))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if !model.heroItems.isEmpty {
                    HeroCarousel(items: model.heroItems, logos: model.heroLogos)
                }
                if !kids && !model.genres.isEmpty {
                    GenreRail(genres: model.genres)
                }
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    MediaRow(title: row.section.title, items: row.items, ranked: row.section.ranked) { router.openDetail($0) }
                    if !kids && index == 1 {
                        SalaBanner()
                    }
                }
                if model.loading && model.rows.count < 3 {
                    LoadingView()
                }
                if let error = model.error, model.rows.isEmpty {
                    MessageView(icon: "exclamationmark.triangle", message: error, actionTitle: "Reintentar") {
                        Task { await model.reload(refresh: false) }
                    }
                }
                if !model.rows.isEmpty { FooterView() }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await model.reload(refresh: true) }
        .task { await model.loadIfNeeded() }
    }
}

struct HeroCarousel: View {
    let items: [MediaItem]
    let logos: [String: String]
    @EnvironmentObject private var router: AppRouter
    @State private var page = 0
    @StateObject private var watcher = PrefsWatcher([MyListStore.name])

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
                hero(item).tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 470)
        .task(id: items.map(\.key)) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                guard !Task.isCancelled, !items.isEmpty else { return }
                withAnimation { page = (page + 1) % items.count }
            }
        }
    }

    private func hero(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(item.backdropUrl.isEmpty ? item.posterUrl : item.backdropUrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, .plixBackground.opacity(0.6), .plixBackground],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text("Destacado en PLIX Lz")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.plixPrimary.opacity(0.85), in: Capsule())
                    .foregroundColor(.black)
                if let logo = logos[item.key], !logo.isEmpty {
                    RemoteImage(logo, contentMode: .fit)
                        .frame(maxWidth: 240, maxHeight: 90, alignment: .leading)
                } else {
                    Text(item.title).font(.system(size: 30, weight: .heavy)).foregroundColor(.white).lineLimit(2)
                }
                Text("\(item.mediaType.label) · \(item.yearText) · ★ \(item.ratingText)")
                    .font(.footnote).foregroundColor(.plixText)
                Text(item.overview.isEmpty ? "Descubre lo mejor del streaming en PLIX Lz." : item.overview)
                    .font(.footnote).foregroundColor(.plixMuted).lineLimit(3)
                HStack(spacing: 10) {
                    Button {
                        if item.mediaType == .movie { router.play(item) } else { router.openDetail(item) }
                    } label: {
                        Label("Reproducir", systemImage: "play.fill")
                    }
                    .buttonStyle(PlixButtonStyle())
                    Button { router.openDetail(item) } label: {
                        Label("Más información", systemImage: "info.circle")
                    }
                    .buttonStyle(PlixButtonStyle(filled: false))
                    Button {
                        let added = MyListStore.toggle(item.id, item.mediaType)
                        AchievementManager.shared.onMyListChanged(count: MyListStore.count)
                        router.showToast(added ? "Agregada a Mi lista" : "Eliminada de Mi lista")
                    } label: {
                        Image(systemName: MyListStore.contains(item.id, item.mediaType) ? "checkmark" : "plus")
                            .frame(width: 44, height: 44)
                            .background(Color.plixSurfaceLight, in: Circle())
                    }
                    .id(watcher.revision)
                    .accessibilityLabel("Mi lista")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 36)
        }
        .contentShape(Rectangle())
    }
}

struct GenreRail: View {
    let genres: [GenreEntry]
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres) { genre in
                    Button { router.open(.genre(genre)) } label: {
                        Text(genre.name)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(Color.plixSurfaceLight, in: Capsule())
                            .foregroundColor(.plixText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct SalaBanner: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        Button { router.select(.sala) } label: {
            BundleImage(name: "banner_sala_virtual.jpg", contentMode: .fill)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unirse a Sala Virtual")
    }
}

struct FooterView: View {
    @State private var showLegal = false
    private let links: [(String, String)] = [
        ("Facebook", "https://www.facebook.com/share/1F9DGiXFMa/"),
        ("Telegram", "https://t.me/LzPlayOficial"),
        ("TikTok", "https://www.tiktok.com/@lzplay.oficial?_r=1&_t=ZS-998Bq9jlITF"),
        ("YouTube", "https://youtube.com/@plix-lzplay?si=ZJeTMgY_GYez4e9N")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().background(Color.plixDivider)
            BrandLogo()
            Text("La plataforma oficial de streaming con lo mejor de series, películas y contenido infantil. Donde quieras, cuando quieras.")
                .font(.footnote).foregroundColor(.plixMuted)
            HStack(spacing: 18) {
                ForEach(links, id: \.0) { link in
                    if let url = URL(string: link.1) {
                        Link(link.0, destination: url).font(.footnote.weight(.semibold))
                    }
                }
            }
            HStack(spacing: 18) {
                ForEach(["Términos de Uso", "Política de Privacidad", "Política de Cookies"], id: \.self) { title in
                    Button(title) { showLegal = true }.font(.caption)
                }
            }
            .foregroundColor(.plixMuted)
            Text("© 2026 PLIX Lz. Todos los derechos reservados.").font(.caption2).foregroundColor(.plixMuted)
        }
        .padding(.horizontal, 16)
        .alert("Legal", isPresented: $showLegal) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("PLIX no aloja videos en sus servidores. El contenido multimedia proviene de fuentes externas ajenas a esta aplicación.\n\nNo se guarda ningún tipo de información personal del usuario en nuestros servidores.\n\nSi eliminás los datos de la app o la desinstalás, toda la información local se borrará de forma permanente.")
        }
    }
}
