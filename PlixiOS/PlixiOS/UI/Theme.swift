import AVFoundation
import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    static let plixBackground = Color(hex: 0x08111F)
    static let plixBackgroundDeep = Color(hex: 0x060D18)
    static let plixSurface = Color(hex: 0x0E1C30)
    static let plixSurfaceLight = Color(hex: 0x13243B)
    static let plixPrimary = Color(hex: 0x3BA7FF)
    static let plixPrimaryDark = Color(hex: 0x1F7FD1)
    static let plixAccent = Color(hex: 0x6EC6FF)
    static let plixText = Color(hex: 0xE8EEF7)
    static let plixMuted = Color(hex: 0x8AA0B8)
    static let plixDivider = Color.white.opacity(0.1)
}

/// Imágenes incluidas en el bundle (Resources/Images): logos de plataformas, banderas, banners.
enum BundleImages {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ fileName: String) -> UIImage? {
        if let cached = cache.object(forKey: fileName as NSString) { return cached }
        let parts = ImageRepo.splitFile(fileName)
        let path = Bundle.main.path(forResource: parts.id, ofType: parts.ext)
            ?? Bundle.main.path(forResource: parts.id, ofType: parts.ext, inDirectory: "Images")
        guard let path, let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: fileName as NSString)
        return image
    }
}

struct BundleImage: View {
    let name: String
    var contentMode: ContentMode = .fit

    var body: some View {
        if let image = BundleImages.image(name) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else {
            Color.plixSurface
        }
    }
}

/// Caché de imágenes remotas en memoria + caché HTTP en disco (sirve sin conexión para lo ya visto).
actor RemoteImageLoader {
    static let shared = RemoteImageLoader()
    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() { memory.countLimit = 400 }

    nonisolated func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            request.setValue(HTTP.appUserAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await HTTP.session.data(for: request), let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    init(_ urlString: String?, contentMode: ContentMode = .fill) {
        let trimmed = urlString?.trimmingCharacters(in: .whitespaces) ?? ""
        url = trimmed.isEmpty ? nil : URL(string: trimmed)
        self.contentMode = contentMode
    }

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    var body: some View {
        ZStack {
            if let shown = image ?? url.flatMap(RemoteImageLoader.shared.cached) {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: contentMode)
            } else {
                LinearGradient(colors: [.plixSurface, .plixSurfaceLight], startPoint: .top, endPoint: .bottom)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            image = await RemoteImageLoader.shared.load(url)
        }
    }
}

/// Fondo de perfil en video (los backdrops .mp4/.webm del repositorio). Silenciado y en bucle.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let queue = AVQueuePlayer()
        queue.isMuted = true
        view.looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = queue
        view.playerLayer.videoGravity = .resizeAspectFill
        queue.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player?.pause()
        uiView.looper = nil
    }
}

struct ProfileBackdropView: View {
    let ref: AvatarRef?

    var body: some View {
        if let ref, let url = ImageRepo.backdropURL(ref) {
            if ImageRepo.isVideo(ref) { LoopingVideoView(url: url) } else { RemoteImage(url: url) }
        } else {
            LinearGradient(colors: [.plixPrimaryDark, .plixBackground], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct AvatarView: View {
    let ref: AvatarRef?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let ref, let url = ImageRepo.avatarURL(ref) {
                RemoteImage(url: url)
            } else {
                ZStack {
                    Color.plixSurfaceLight
                    Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundColor(.plixMuted)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

// MARK: Tarjetas y filas

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 118
    var rank: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RemoteImage(item.posterUrl)
                    .frame(width: width, height: width * 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                if let rank {
                    Text("\(rank)")
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 4)
                        .padding(.leading, 6)
                }
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 8))
                    Text(item.ratingText).font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.black.opacity(0.65), in: Capsule())
                .foregroundColor(.yellow)
                .padding(6)
                .frame(width: width, height: width * 1.5, alignment: .bottomTrailing)
            }
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.plixText)
                .lineLimit(1)
            Text("\(item.mediaType.label) · \(item.yearText)")
                .font(.system(size: 10))
                .foregroundColor(.plixMuted)
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }
}

struct MediaRow: View {
    let title: String
    let items: [MediaItem]
    var ranked = false
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.plixText)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
                        Button { onSelect(item) } label: {
                            PosterCard(item: item, rank: ranked ? index + 1 : nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct MediaGrid: View {
    let items: [MediaItem]
    let onSelect: (MediaItem) -> Void
    var onReachEnd: (() -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.key) { item in
                Button { onSelect(item) } label: {
                    GeometryReader { proxy in
                        PosterCard(item: item, width: proxy.size.width)
                    }
                    .aspectRatio(0.5, contentMode: .fit)
                }
                .buttonStyle(.plain)
                .onAppear { if item.key == items.last?.key { onReachEnd?() } }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: Estados

struct LoadingView: View {
    var message = "Cargando contenido…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.plixPrimary).scaleEffect(1.2)
            Text(message).font(.footnote).foregroundColor(.plixMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

struct MessageView: View {
    let icon: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundColor(.plixMuted)
            Text(message).font(.subheadline).foregroundColor(.plixText).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(PlixButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct PlixButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 18).padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(filled ? Color.plixPrimary : Color.plixSurfaceLight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundColor(filled ? .black : .plixText)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Sin conexión. Puedes ver tu lista, historial y logros guardados.")
                .font(.caption)
                .lineLimit(2)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.9))
    }
}

struct AchievementToastView: View {
    let achievement: Achievement
    let extra: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(achievement.emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text("¡LOGRO DESBLOQUEADO!").font(.system(size: 11, weight: .heavy)).foregroundColor(.plixAccent)
                Text(extra > 0 ? "\(achievement.name) · +\(extra)" : achievement.name)
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.plixText)
                Text(achievement.description).font(.caption).foregroundColor(.plixMuted).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.plixSurface.opacity(0.97), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.plixPrimary.opacity(0.6), lineWidth: 1))
        .shadow(color: .plixPrimary.opacity(0.35), radius: 14)
        .padding(.horizontal, 16)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 20, weight: .bold)).foregroundColor(.plixText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Logo del header: "PLIX Lz" por defecto o el logo LzPlay desbloqueado en Diseño.
struct BrandLogo: View {
    @StateObject private var watcher = PrefsWatcher([HeaderLogoStore.name])
    var height: CGFloat = 26

    var body: some View {
        Group {
            if HeaderLogoStore.selected == HeaderLogoStore.lzPlay {
                BundleImage(name: "logo_lzplay.png").frame(height: height)
            } else {
                HStack(spacing: 2) {
                    Text("PLIX").font(.system(size: height * 0.9, weight: .black)).foregroundColor(.plixText)
                    Text("Lz").font(.system(size: height * 0.9, weight: .black)).foregroundColor(.plixPrimary)
                }
            }
        }
        .id(watcher.revision)
        .accessibilityLabel("PLIX Lz")
    }
}

/// Publica un cambio cada vez que se modifica alguno de los archivos de preferencias indicados
/// (o cualquiera, si la lista está vacía). Así las pantallas se refrescan tras restaurar un respaldo.
final class PrefsWatcher: ObservableObject {
    @Published private(set) var revision = 0
    private var token: NSObjectProtocol?

    init(_ names: [String] = []) {
        let watched = Set(names)
        token = NotificationCenter.default.addObserver(forName: .plixPrefsChanged, object: nil, queue: .main) { [weak self] note in
            guard let name = note.object as? String, watched.isEmpty || watched.contains(name) else { return }
            self?.revision += 1
        }
    }

    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
