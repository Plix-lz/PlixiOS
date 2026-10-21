import SwiftUI

/// Películas / Series: IDs del catálogo host (más nuevos primero), cargados por lotes desde TMDB.
@MainActor
final class HostCatalogModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var refs: [ContentRef] = []
    private var cursor = 0
    private let type: MediaType
    private static let batch = 24

    init(type: MediaType) { self.type = type }

    var finished: Bool { !refs.isEmpty && cursor >= refs.count }

    func start() async {
        guard refs.isEmpty, !loading else { return }
        loading = true
        error = nil
        do {
            refs = try await TMDBClient.shared.hostCatalog(type)
            loading = false
            await loadMore()
        } catch {
            loading = false
            self.error = error.localizedDescription.isEmpty ? "No se pudo cargar el catálogo." : error.localizedDescription
        }
    }

    func loadMore() async {
        guard !loading, cursor < refs.count else { return }
        loading = true
        let slice = Array(refs[cursor..<min(cursor + Self.batch, refs.count)])
        cursor += slice.count
        let loaded = await TMDBClient.shared.itemsByIds(slice)
        let known = Set(items.map(\.key))
        items.append(contentsOf: loaded.filter { !known.contains($0.key) })
        loading = false
        if loaded.isEmpty && items.isEmpty && cursor < refs.count { await loadMore() }
    }
}

struct HostCatalogView: View {
    let type: MediaType
    @StateObject private var model: HostCatalogModel
    @EnvironmentObject private var router: AppRouter

    init(type: MediaType) {
        self.type = type
        _model = StateObject(wrappedValue: HostCatalogModel(type: type))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: type == .movie ? "Películas" : "Series").padding(.horizontal, 16)
                if let error = model.error {
                    MessageView(icon: "exclamationmark.triangle", message: error, actionTitle: "Reintentar") {
                        Task { await model.start() }
                    }
                } else if model.items.isEmpty && !model.loading && model.finished {
                    MessageView(icon: "film", message: "No hay títulos disponibles en este apartado.")
                } else {
                    MediaGrid(items: model.items, onSelect: { router.openDetail($0) }) {
                        Task { await model.loadMore() }
                    }
                }
                if model.loading { LoadingView() }
            }
            .padding(.vertical, 12)
        }
        .task { await model.start() }
        .id(type)
    }
}

@MainActor
final class GenreModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var page = 1
    private var hasMore = true
    let genre: GenreEntry

    init(genre: GenreEntry) { self.genre = genre }

    func loadMore() async {
        guard !loading, hasMore else { return }
        loading = true
        do {
            let result = try await TMDBClient.shared.genrePage(genre, page: page)
            page += 1
            hasMore = result.hasMore
            let known = Set(items.map(\.key))
            items.append(contentsOf: result.items.filter { !known.contains($0.key) })
            error = nil
        } catch {
            if items.isEmpty { self.error = "No se pudo cargar el contenido del género." }
            hasMore = false
        }
        loading = false
    }

    func retry() async {
        hasMore = true
        error = nil
        await loadMore()
    }
}

struct GenreContentView: View {
    @StateObject private var model: GenreModel
    @EnvironmentObject private var router: AppRouter

    init(genre: GenreEntry) { _model = StateObject(wrappedValue: GenreModel(genre: genre)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = model.error {
                    MessageView(icon: "exclamationmark.triangle", message: error, actionTitle: "Reintentar") {
                        Task { await model.retry() }
                    }
                } else if model.items.isEmpty && !model.loading {
                    MessageView(icon: "film", message: "No hay títulos disponibles en este género.")
                } else {
                    MediaGrid(items: model.items, onSelect: { router.openDetail($0) }) { Task { await model.loadMore() } }
                }
                if model.loading { LoadingView() }
            }
            .padding(.vertical, 12)
        }
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle(model.genre.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.items.isEmpty { await model.loadMore() } }
    }
}

// MARK: Búsqueda

struct SearchView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var searching = false
    @State private var searched = false
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.plixMuted)
                TextField("Buscar películas, series…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit(runSearch)
                if !query.isEmpty {
                    Button { query = ""; results = []; searched = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.plixMuted)
                    }
                    .accessibilityLabel("Limpiar búsqueda")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
            .padding(16)

            ScrollView {
                if searching {
                    LoadingView(message: "Buscando resultados…")
                } else if results.isEmpty {
                    MessageView(icon: searched ? "magnifyingglass" : "text.magnifyingglass",
                                message: searched ? "No encontramos resultados para tu búsqueda." : "Escribe un título y pulsa buscar para ver resultados.")
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Resultados de búsqueda").padding(.horizontal, 16)
                        MediaGrid(items: results, onSelect: { router.openDetail($0) })
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { focused = true }
        .onDisappear { task?.cancel() }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        AchievementManager.shared.onSearchSubmitted(trimmed)
        task?.cancel()
        searching = true
        task = Task {
            let found = await TMDBClient.shared.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            searched = true
            searching = false
        }
    }
}

// MARK: Mi lista / Historial

struct LibraryView: View {
    enum Mode { case myList, history }
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todos", unstarted = "Sin empezar", started = "Empezó", series = "Series", movies = "Películas"
        var id: String { rawValue }
    }

    let mode: Mode
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watcher = PrefsWatcher([MyListStore.name, "plix_content_history", PlaybackProgressStore.name])
    @State private var items: [MediaItem] = []
    @State private var filter: Filter = .all
    @State private var loading = false
    @State private var confirmClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(text: mode == .myList ? "Mi lista" : "Historial")
                    if mode == .history && !items.isEmpty {
                        Button("Eliminar") { confirmClear = true }.foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { option in
                            Button { filter = option } label: {
                                Text(option.rawValue).font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 14).frame(height: 34)
                                    .background(filter == option ? Color.plixPrimary : Color.plixSurfaceLight, in: Capsule())
                                    .foregroundColor(filter == option ? .black : .plixText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if loading && items.isEmpty {
                    LoadingView()
                } else if filtered.isEmpty {
                    MessageView(icon: mode == .myList ? "heart" : "clock",
                                message: items.isEmpty
                                    ? (mode == .myList ? "Todavía no agregaste contenidos a Mi lista." : "Todavía no abriste películas o series.")
                                    : "No hay títulos en este filtro.")
                } else {
                    MediaGrid(items: filtered, onSelect: { router.openDetail($0) })
                }
            }
            .padding(.vertical, 12)
        }
        .task(id: watcher.revision) { await load() }
        .confirmationDialog("¿Eliminar historial?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { ContentEntriesStore.history.clear() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrarán todos los títulos guardados en el historial.")
        }
    }

    private var filtered: [MediaItem] {
        switch filter {
        case .all: return items
        case .unstarted: return items.filter { !PlaybackProgressStore.hasProgress($0) }
        case .started: return items.filter { PlaybackProgressStore.hasProgress($0) }
        case .series: return items.filter { $0.mediaType == .tv }
        case .movies: return items.filter { $0.mediaType == .movie }
        }
    }

    private func load() async {
        switch mode {
        case .history:
            items = ContentEntriesStore.history.list()
        case .myList:
            loading = true
            let refs = MyListStore.refs()
            let cached = Dictionary(ContentEntriesStore.history.list().map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            var result: [MediaItem] = []
            var missing: [ContentRef] = []
            for ref in refs {
                let key = (ref.type == ContentType.series ? "tv" : "movie") + ":\(ref.id)"
                if let hit = cached[key] { result.append(hit) } else { missing.append(ref) }
            }
            if !missing.isEmpty { result += await TMDBClient.shared.itemsByIds(missing) }
            let order = Dictionary(uniqueKeysWithValues: refs.enumerated().map {
                (($0.element.type == ContentType.series ? "tv" : "movie") + ":\($0.element.id)", $0.offset)
            })
            items = result.sorted { (order[$0.key] ?? 0) < (order[$1.key] ?? 0) }
            loading = false
        }
    }
}

// MARK: Plataformas

struct PlatformsView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var platforms: [PlatformItem] = []
    @State private var loading = false
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(text: "Plataformas").padding(.horizontal, 16)
                if loading && platforms.isEmpty {
                    LoadingView()
                } else if let error {
                    MessageView(icon: "exclamationmark.triangle", message: error, actionTitle: "Reintentar") { Task { await load() } }
                } else if platforms.isEmpty {
                    MessageView(icon: "square.grid.2x2", message: "No hay plataformas disponibles.")
                } else {
                    group("Streaming", platforms.filter { $0.kind == .streaming })
                    group("Estudios y colecciones", platforms.filter { $0.kind == .collection })
                }
            }
            .padding(.vertical, 12)
        }
        .task { if platforms.isEmpty { await load() } }
    }

    @ViewBuilder
    private func group(_ title: String, _ list: [PlatformItem]) -> some View {
        if !list.isEmpty {
            Text(title).font(.headline).foregroundColor(.plixMuted).padding(.horizontal, 16)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(list) { platform in
                    Button { router.open(.platform(platform)) } label: { PlatformTile(platform: platform) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            platforms = try await PlatformRepository.shared.loadPlatforms()
        } catch {
            self.error = "No se pudo cargar el catálogo de plataformas."
        }
        loading = false
    }
}

struct PlatformTile: View {
    let platform: PlatformItem

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let embedded = platform.embeddedLogo {
                    BundleImage(name: embedded, contentMode: .fill)
                } else if let logo = platform.logoUrl {
                    RemoteImage(logo)
                } else {
                    ZStack {
                        Color.plixSurfaceLight
                        Text(String(platform.name.prefix(2)).uppercased()).font(.title2.bold()).foregroundColor(.plixText)
                    }
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(platform.name).font(.caption).foregroundColor(.plixText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlatformContentView: View {
    let platform: PlatformItem
    @StateObject private var loader: PlatformContentLoader
    @EnvironmentObject private var router: AppRouter

    init(platform: PlatformItem) {
        self.platform = platform
        _loader = StateObject(wrappedValue: PlatformContentLoader(platform: platform))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if loader.failed {
                    MessageView(icon: "exclamationmark.triangle", message: "No se pudo cargar el catálogo de plataformas.")
                } else if loader.items.isEmpty && loader.finished {
                    MessageView(icon: "film", message: "No hay títulos disponibles en esta plataforma.")
                } else {
                    MediaGrid(items: loader.items, onSelect: { router.openDetail($0) }) { Task { await loader.loadMore() } }
                }
                if loader.loading { LoadingView() }
                if loader.finished && !loader.items.isEmpty {
                    Text("Eso es todo.").font(.footnote).foregroundColor(.plixMuted)
                }
            }
            .padding(.vertical, 12)
        }
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle(platform.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if loader.items.isEmpty && !loader.finished { await loader.start() } }
    }
}
