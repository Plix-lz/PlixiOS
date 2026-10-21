import SwiftUI
import WebKit

struct DetailHeader: View {
    let backdrop: String
    let poster: String
    let title: String
    let meta: String
    let rating: Double
    let voteCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(backdrop.isEmpty ? poster : backdrop)
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, .plixBackground], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 14) {
                RemoteImage(poster)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 22, weight: .heavy)).foregroundColor(.white).lineLimit(3)
                    Text(meta).font(.footnote).foregroundColor(.plixText)
                    if rating > 0 {
                        Label(String(format: "%.1f (%d)", rating, voteCount), systemImage: "star.fill")
                            .font(.footnote.weight(.semibold)).foregroundColor(.yellow)
                    }
                }
            }
            .padding(.horizontal, 16)
            .offset(y: 50)
        }
        .padding(.bottom, 50)
    }
}

struct DetailActions: View {
    let item: MediaItem
    let trailerKey: String
    let playTitle: String
    let onPlay: () -> Void
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watcher = PrefsWatcher([MyListStore.name])

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) { Label(playTitle, systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(PlixButtonStyle())
            Button {
                let added = MyListStore.toggle(item.id, item.mediaType)
                AchievementManager.shared.onMyListChanged(count: MyListStore.count)
                router.showToast(added ? "Agregada a Mi lista" : "Eliminada de Mi lista")
            } label: {
                Label("Mi lista", systemImage: MyListStore.contains(item.id, item.mediaType) ? "checkmark" : "plus")
            }
            .buttonStyle(PlixButtonStyle(filled: false))
            .id(watcher.revision)
            if !trailerKey.isEmpty {
                Button { router.trailerKey = trailerKey } label: { Image(systemName: "film").frame(width: 22) }
                    .buttonStyle(PlixButtonStyle(filled: false))
                    .accessibilityLabel("Ver tráiler")
            }
        }
        .padding(.horizontal, 16)
    }
}

struct CastRow: View {
    let cast: [CastMember]

    var body: some View {
        if !cast.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Elenco principal").font(.headline).foregroundColor(.plixText).padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(cast) { member in
                            VStack(spacing: 4) {
                                RemoteImage(member.profileUrl).frame(width: 70, height: 70).clipShape(Circle())
                                Text(member.name).font(.caption2.weight(.semibold)).foregroundColor(.plixText).lineLimit(2)
                                Text(member.character).font(.caption2).foregroundColor(.plixMuted).lineLimit(1)
                            }
                            .frame(width: 80)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct InfoLine: View {
    let label: String
    let value: String
    var body: some View {
        (Text(label + ": ").bold() + Text(value.isEmpty ? "No disponible" : value))
            .font(.footnote).foregroundColor(.plixMuted)
    }
}

// MARK: Película

struct MovieDetailView: View {
    let item: MediaItem
    @EnvironmentObject private var router: AppRouter
    @State private var detail: MovieDetail?
    @State private var failed = false

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 18) {
                    DetailHeader(backdrop: detail.backdropUrl, poster: detail.posterUrl, title: detail.title,
                                 meta: [detail.year, detail.runtimeMinutes > 0 ? "\(detail.runtimeMinutes) min" : "", detail.genres.prefix(3).joined(separator: ", ")]
                                    .filter { !$0.isEmpty }.joined(separator: " · "),
                                 rating: detail.rating, voteCount: detail.voteCount)
                    DetailActions(item: detail.asMediaItem, trailerKey: detail.trailerKey, playTitle: "Reproducir") {
                        router.play(detail.asMediaItem)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sinopsis").font(.headline).foregroundColor(.plixText)
                        Text(detail.overview.isEmpty ? "Descubre lo mejor del streaming en PLIX Lz." : detail.overview)
                            .font(.subheadline).foregroundColor(.plixMuted)
                        InfoLine(label: "Dirección", value: detail.director)
                        InfoLine(label: "Idiomas", value: detail.languages.joined(separator: ", "))
                    }
                    .padding(.horizontal, 16)
                    CastRow(cast: detail.cast)
                    if !detail.related.isEmpty {
                        MediaRow(title: "Contenido relacionado", items: detail.related) { router.openDetail($0) }
                    }
                }
                .padding(.bottom, 30)
            } else if failed {
                MessageView(icon: "exclamationmark.triangle", message: "No pudimos cargar esta película.", actionTitle: "Reintentar") {
                    failed = false
                    Task { await load() }
                }
            } else {
                LoadingView()
            }
        }
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if detail == nil { await load() } }
    }

    private func load() async {
        do {
            let loaded = try await TMDBClient.shared.movieDetail(item.id)
            detail = loaded
            ContentEntriesStore.history.record(loaded.asMediaItem)
            GenreTasteStore.record(.movie, genreIds: loaded.genreIds)
            AchievementManager.shared.cacheContentMeta(contentId: loaded.id, series: false, genres: loaded.genres, origins: loaded.countries)
        } catch {
            failed = true
        }
    }
}

// MARK: Serie

struct SeriesDetailView: View {
    let item: MediaItem
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watcher = PrefsWatcher([PlaybackProgressStore.name])
    @State private var detail: SeriesDetail?
    @State private var failed = false
    @State private var season = 1
    @State private var episodes: [EpisodeItem] = []
    @State private var loadingEpisodes = false

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 18) {
                    DetailHeader(backdrop: detail.backdropUrl, poster: detail.posterUrl, title: detail.title,
                                 meta: [detail.year, "\(detail.seasonsCount) temporada(s)", detail.genres.prefix(3).joined(separator: ", ")]
                                    .filter { !$0.isEmpty }.joined(separator: " · "),
                                 rating: detail.rating, voteCount: detail.voteCount)
                    DetailActions(item: detail.asMediaItem, trailerKey: detail.trailerKey, playTitle: continueTitle) {
                        let episode = PlaybackProgressStore.lastEpisode(detail.id, season, fallback: episodes.first?.episode ?? 1)
                        router.play(detail.asMediaItem, season: season, episode: episode)
                    }
                    .disabled(episodes.isEmpty)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sinopsis").font(.headline).foregroundColor(.plixText)
                        Text(detail.overview.isEmpty ? "Descubre lo mejor del streaming en PLIX Lz." : detail.overview)
                            .font(.subheadline).foregroundColor(.plixMuted)
                        InfoLine(label: "Creadores", value: detail.creators.joined(separator: ", "))
                        InfoLine(label: "Cadena", value: detail.network)
                        InfoLine(label: "Idiomas", value: detail.languages.joined(separator: ", "))
                    }
                    .padding(.horizontal, 16)
                    episodesSection(detail)
                    CastRow(cast: detail.cast)
                    if !detail.related.isEmpty {
                        MediaRow(title: "Contenido relacionado", items: detail.related) { router.openDetail($0) }
                    }
                }
                .padding(.bottom, 30)
            } else if failed {
                MessageView(icon: "exclamationmark.triangle", message: "No pudimos cargar esta serie.", actionTitle: "Reintentar") {
                    failed = false
                    Task { await load() }
                }
            } else {
                LoadingView()
            }
        }
        .background(Color.plixBackground.ignoresSafeArea())
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if detail == nil { await load() } }
    }

    private var continueTitle: String {
        guard let detail else { return "Reproducir" }
        let last = PlaybackProgressStore.lastEpisode(detail.id, season, fallback: 0)
        return last > 0 ? "Continuar T\(season) E\(last)" : "Reproducir"
    }

    @ViewBuilder
    private func episodesSection(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Episodios").font(.headline).foregroundColor(.plixText)
                Spacer()
                if !detail.seasons.isEmpty {
                    Menu {
                        ForEach(detail.seasons) { info in
                            Button(info.name.isEmpty ? "Temporada \(info.number)" : info.name) {
                                season = info.number
                                PlaybackProgressStore.setSelectedSeason(detail.id, info.number)
                                Task { await loadEpisodes(detail.id) }
                            }
                        }
                    } label: {
                        Label("Temporada \(season)", systemImage: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).frame(height: 36)
                            .background(Color.plixSurfaceLight, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
            if loadingEpisodes {
                LoadingView(message: "Cargando episodios…")
            } else if episodes.isEmpty {
                Text("Esta temporada no tiene episodios disponibles.").font(.footnote).foregroundColor(.plixMuted)
                    .padding(.horizontal, 16)
            } else {
                let watched = PlaybackProgressStore.watchedEpisodes(detail.id, season)
                LazyVStack(spacing: 10) {
                    ForEach(episodes) { episode in
                        Button {
                            router.play(detail.asMediaItem, season: episode.season, episode: episode.episode)
                        } label: {
                            EpisodeRow(episode: episode, watched: watched.contains(episode.episode))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .id(watcher.revision)
            }
        }
    }

    private func load() async {
        do {
            let loaded = try await TMDBClient.shared.seriesDetail(item.id)
            detail = loaded
            ContentEntriesStore.history.record(loaded.asMediaItem)
            GenreTasteStore.record(.tv, genreIds: loaded.genreIds)
            AchievementManager.shared.cacheContentMeta(contentId: loaded.id, series: true, genres: loaded.genres, origins: loaded.countries)
            AchievementManager.shared.setSeriesSeasonGoal(loaded.id, seasons: loaded.seasons.count)
            let first = loaded.seasons.first?.number ?? 1
            season = PlaybackProgressStore.selectedSeason(loaded.id, fallback: first)
            if !loaded.seasons.contains(where: { $0.number == season }) { season = first }
            await loadEpisodes(loaded.id)
        } catch {
            failed = true
        }
    }

    private func loadEpisodes(_ id: Int) async {
        loadingEpisodes = true
        episodes = (try? await TMDBClient.shared.seasonEpisodes(seriesId: id, season: season)) ?? []
        AchievementManager.shared.registerSeasonEpisodes(id, season: season, numbers: episodes.map(\.episode))
        loadingEpisodes = false
    }
}

struct EpisodeRow: View {
    let episode: EpisodeItem
    let watched: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(episode.stillUrl).frame(width: 130, height: 74).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("E\(episode.episode)").font(.caption2.bold()).padding(4)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4)).padding(4)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(episode.episode). \(episode.name)").font(.subheadline.weight(.semibold)).foregroundColor(.plixText).lineLimit(2)
                if !episode.overview.isEmpty {
                    Text(episode.overview).font(.caption).foregroundColor(.plixMuted).lineLimit(2)
                }
                if watched {
                    Label("Episodio visto", systemImage: "eye.fill").font(.caption2).foregroundColor(.plixPrimary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill").font(.title2).foregroundColor(.plixPrimary)
        }
        .padding(8)
        .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Tráiler

/// Tráiler de YouTube en el reproductor embebido oficial (youtube-nocookie). Sin puentes JS.
struct TrailerView: View {
    let videoKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tráiler").font(.headline)
                Spacer()
                Button("Cerrar tráiler") { dismiss() }
            }
            .padding()
            YouTubeEmbed(videoKey: videoKey)
                .aspectRatio(16 / 9, contentMode: .fit)
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

struct YouTubeEmbed: UIViewRepresentable {
    let videoKey: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let safeKey = videoKey.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        guard !safeKey.isEmpty, context.coordinator.loadedKey != safeKey else { return }
        context.coordinator.loadedKey = safeKey
        let html = """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;background:#000}iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(safeKey)?playsinline=1&autoplay=1&rel=0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
        """
        view.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedKey = ""

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let host = action.request.url?.host?.lowercased() ?? ""
            let allowed = action.request.url?.scheme == "about" || host.hasSuffix("youtube-nocookie.com") || host.hasSuffix("youtube.com")
                || host.hasSuffix("ytimg.com") || host.hasSuffix("googlevideo.com") || host.hasSuffix("google.com") || host.hasSuffix("gstatic.com")
            decisionHandler(allowed && action.navigationType != .linkActivated ? .allow : .cancel)
        }
    }
}
