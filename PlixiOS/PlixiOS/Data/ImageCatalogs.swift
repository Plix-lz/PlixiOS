import Foundation

/// Repositorio público de imágenes (`Plix-lz/img`): ICONOS, BACKDROPS y STICKERS.
enum ImageRepo {
    static let rawBase = "https://raw.githubusercontent.com/Plix-lz/img/main/"
    static let treeURL = "https://api.github.com/repos/Plix-lz/img/git/trees/main?recursive=1"
    static let rootPack = "-"
    static let videoExtensions: Set<String> = ["mp4", "webm", "m4v", "mov"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]

    static func encode(_ segment: String) -> String { segment.replacingOccurrences(of: " ", with: "%20") }

    static func splitFile(_ fileName: String) -> (id: String, ext: String) {
        guard let dot = fileName.lastIndex(of: "."), dot > fileName.startIndex else { return (fileName, "") }
        return (String(fileName[..<dot]), String(fileName[fileName.index(after: dot)...]).lowercased())
    }

    static func avatarURL(_ ref: AvatarRef) -> URL? {
        guard !ref.folder.isEmpty, !ref.pack.isEmpty, !ref.id.isEmpty else { return nil }
        let ext = ref.ext.isEmpty ? "jpg" : ref.ext.replacingOccurrences(of: ".", with: "")
        return URL(string: rawBase + "ICONOS/" + encode(ref.folder) + "/" + encode(ref.pack) + "/" + encode(ref.id) + "." + ext)
    }

    static func backdropURL(_ ref: AvatarRef) -> URL? {
        guard !ref.folder.isEmpty, !ref.pack.isEmpty, !ref.id.isEmpty else { return nil }
        let ext = ref.ext.isEmpty ? "jpg" : ref.ext.replacingOccurrences(of: ".", with: "")
        let pack = ref.pack == rootPack ? "" : encode(ref.pack) + "/"
        return URL(string: rawBase + "BACKDROPS/" + encode(ref.folder) + "/" + pack + encode(ref.id) + "." + ext)
    }

    static func isVideo(_ ref: AvatarRef) -> Bool { videoExtensions.contains(ref.ext.lowercased()) }
}

enum StickerCatalog {
    static let rawBase = ImageRepo.rawBase + "STICKERS/"

    static func normalizeKey(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let slash = value.lastIndex(of: "/"), value.index(after: slash) < value.endIndex {
            value = String(value[value.index(after: slash)...])
        }
        if value.allSatisfy({ $0.isASCII && $0.isNumber }) { return value + ".jpg" }
        return value
    }

    static func isImageFile(_ name: String) -> Bool {
        ImageRepo.imageExtensions.contains(ImageRepo.splitFile(name).ext)
    }

    static func url(for key: String) -> URL? {
        guard let normalized = normalizeKey(key) else { return nil }
        return URL(string: rawBase + ImageRepo.encode(normalized))
    }
}

struct ImagePackSection: Identifiable, Hashable {
    let folder: String
    let pack: String
    let items: [AvatarRef]
    var id: String { folder + "/" + pack }
    var title: String { pack == ImageRepo.rootPack ? folder : "\(folder) · \(pack)" }
}

/// Lee el árbol de GitHub una vez y lo cachea 6 h (como los repositorios de catálogo de Android).
actor ImageCatalogRepository {
    static let shared = ImageCatalogRepository()
    private static let ttlMs: Int64 = 6 * 60 * 60 * 1000
    private let cache = PrefsRegistry.shared.prefs("plix_cache_img_tree")
    private var paths: [String]?

    private func treePaths(force: Bool) async throws -> [String] {
        if !force, let paths { return paths }
        let fetchedAt = cache.long("fetched_at")
        let stored = (JSONUtil.array(from: cache.string("paths", "[]")) as? [String]) ?? []
        if !force, !stored.isEmpty, Clock.nowMs - fetchedAt < Self.ttlMs {
            paths = stored
            return stored
        }
        do {
            let root = try await HTTP.json(ImageRepo.treeURL, headers: ["Accept": "application/vnd.github+json"])
            let fresh = root.objects("tree").filter { $0.str("type") == "blob" }.map { $0.str("path") }
            guard !fresh.isEmpty else { throw PlixError.invalidResponse }
            cache.edit { values in
                values["paths"] = .string(JSONUtil.string(fresh))
                values["fetched_at"] = .long(Clock.nowMs)
            }
            paths = fresh
            return fresh
        } catch {
            if !stored.isEmpty {
                paths = stored
                return stored
            }
            throw error
        }
    }

    func avatarSections(force: Bool = false) async throws -> [ImagePackSection] {
        var grouped: [String: [AvatarRef]] = [:]
        for path in try await treePaths(force: force) where path.hasPrefix("ICONOS/") {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, StickerCatalog.isImageFile(parts[3]) else { continue }
            let file = ImageRepo.splitFile(parts[3])
            guard !file.id.isEmpty else { continue }
            grouped[parts[1] + "\u{0}" + parts[2], default: []].append(AvatarRef(folder: parts[1], pack: parts[2], id: file.id, ext: file.ext))
        }
        return sections(grouped)
    }

    func backdropSections(force: Bool = false) async throws -> [ImagePackSection] {
        var grouped: [String: [AvatarRef]] = [:]
        for path in try await treePaths(force: force) where path.hasPrefix("BACKDROPS/") {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            let folder: String, pack: String, fileName: String
            if parts.count == 4 { (folder, pack, fileName) = (parts[1], parts[2], parts[3]) }
            else if parts.count == 3 { (folder, pack, fileName) = (parts[1], ImageRepo.rootPack, parts[2]) }
            else { continue }
            let file = ImageRepo.splitFile(fileName)
            guard !file.id.isEmpty,
                  ImageRepo.imageExtensions.contains(file.ext) || ImageRepo.videoExtensions.contains(file.ext) else { continue }
            grouped[folder + "\u{0}" + pack, default: []].append(AvatarRef(folder: folder, pack: pack, id: file.id, ext: file.ext))
        }
        return sections(grouped)
    }

    func stickers(force: Bool = false) async throws -> [String] {
        let keys = try await treePaths(force: force).compactMap { path -> String? in
            guard path.hasPrefix("STICKERS/") else { return nil }
            let relative = String(path.dropFirst("STICKERS/".count))
            guard !relative.contains("/"), StickerCatalog.isImageFile(relative) else { return nil }
            return StickerCatalog.normalizeKey(relative)
        }
        return keys.sorted { a, b in
            let na = Int(a.prefix(while: { $0.isNumber }))
            let nb = Int(b.prefix(while: { $0.isNumber }))
            switch (na, nb) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        }
    }

    private func sections(_ grouped: [String: [AvatarRef]]) -> [ImagePackSection] {
        grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.compactMap { key in
            let parts = key.split(separator: "\u{0}", maxSplits: 1).map(String.init)
            guard parts.count == 2, let items = grouped[key] else { return nil }
            return ImagePackSection(folder: parts[0], pack: parts[1], items: items.sorted { $0.id < $1.id })
        }
    }
}
