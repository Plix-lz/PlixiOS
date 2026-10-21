import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home, movies, series, kids, platforms, myList, sala, history, achievements, design, account
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .movies: return "Películas"
        case .series: return "Series"
        case .kids: return "Infantil"
        case .platforms: return "Plataformas"
        case .myList: return "Mi lista"
        case .sala: return "Sala"
        case .history: return "Historial"
        case .achievements: return "Logros"
        case .design: return "Diseño"
        case .account: return "Cuenta"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film.fill"
        case .series: return "tv.fill"
        case .kids: return "face.smiling.fill"
        case .platforms: return "square.grid.2x2.fill"
        case .myList: return "heart.fill"
        case .sala: return "person.2.wave.2.fill"
        case .history: return "clock.arrow.circlepath"
        case .achievements: return "trophy.fill"
        case .design: return "paintpalette.fill"
        case .account: return "person.crop.circle.fill"
        }
    }
}

enum Route: Hashable {
    case detail(MediaItem)
    case genre(GenreEntry)
    case platform(PlatformItem)
    case publicProfile(String)
    case findFriends
    case friendRequests
    case watchRoom
}

/// Contexto del selector de servidores.
struct ServerPickerContext: Identifiable {
    let id = UUID()
    let item: MediaItem
    let season: Int
    let episode: Int
    /// Invitado de Cine Virtual: debe elegir un servidor parecido al del anfitrión.
    let watchPartyGuest: Bool
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var section: MainSection = .home
    @Published var path = NavigationPath()
    @Published var drawerOpen = false
    @Published var searchActive = false
    @Published var serverPicker: ServerPickerContext?
    @Published var playback: PlaybackRequest?
    @Published var trailerKey: String?
    @Published var toast: String?

    func select(_ newSection: MainSection) {
        section = newSection
        path = NavigationPath()
        searchActive = false
        withAnimation(.easeOut(duration: 0.2)) { drawerOpen = false }
    }

    func open(_ route: Route) { path.append(route) }

    func openDetail(_ item: MediaItem) { path.append(Route.detail(item)) }

    func play(_ item: MediaItem, season: Int = 0, episode: Int = 0) {
        serverPicker = ServerPickerContext(item: item, season: season, episode: episode, watchPartyGuest: false)
    }

    func startPlayback(_ request: PlaybackRequest) {
        serverPicker = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.playback = request
        }
    }

    func showToast(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if self.toast == message { self.toast = nil }
        }
    }
}
