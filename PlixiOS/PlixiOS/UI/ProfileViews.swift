import SwiftUI
import UIKit

// MARK: Cuenta

struct AccountView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watcher = PrefsWatcher([ProfileImageStore.avatar.name, ProfileImageStore.backdrop.name,
                                                     ProfileBioStore.name, StickerStore.name])

    var body: some View {
        Group {
            if !account.cloudAvailable {
                MessageView(icon: "icloud.slash", message: "La cuenta en la nube necesita Firebase. Esta compilación no incluye GoogleService-Info.plist; el resto de la app funciona sin cuenta.")
            } else if account.isSignedIn {
                AccountProfileView().id(watcher.revision)
            } else {
                SignInFormView()
            }
        }
    }
}

struct SignInFormView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var router: AppRouter
    @State private var creating = false
    @State private var username = ""
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("CUENTA DE RESPALDO").font(.caption.bold()).foregroundColor(.plixMuted)
                Picker("", selection: $creating) {
                    Text("Iniciar sesión").tag(false)
                    Text("Crear cuenta").tag(true)
                }
                .pickerStyle(.segmented)

                field("Nombre de usuario") {
                    TextField("Usuario", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                }
                field("PIN") {
                    SecureField("Tu PIN (solo números)", text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                }
                if creating {
                    field("Confirmar PIN") {
                        SecureField("Repite el PIN", text: $confirmPin).keyboardType(.numberPad)
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundColor(.orange)
                }
                Button(busy ? "Conectando…" : (creating ? "Crear cuenta" : "Iniciar sesión"), action: submit)
                    .buttonStyle(PlixButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(busy)
                Text("Tus preferencias, Mi lista, historial, progreso y logros se respaldan en la nube con esta cuenta. El PIN se guarda solo en el Llavero (Keychain) del iPhone.")
                    .font(.caption).foregroundColor(.plixMuted)
            }
            .padding(20)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundColor(.plixMuted)
            content()
                .padding(.horizontal, 12).frame(height: 46)
                .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func submit() {
        do {
            try AccountManager.validate(username: username, pin: pin)
            if creating && pin != confirmPin { throw PlixError.message("Los PIN no coinciden.") }
        } catch {
            self.error = error.localizedDescription
            return
        }
        busy = true
        error = nil
        Task {
            do {
                try await account.signIn(username: username, pin: pin)
                pin = ""
                confirmPin = ""
                router.showToast("Sesión iniciada")
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

struct AccountProfileView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var router: AppRouter
    @State private var showPin = false
    @State private var editingBio = false
    @State private var bioDraft = ""
    @State private var picker: ProfileImageKind?
    @State private var showStickers = false
    @State private var friendsCount: Int?
    @State private var saving = false
    @State private var confirmSignOut = false

    var body: some View {
        let avatar = ProfileImageStore.avatar.current
        let backdrop = ProfileImageStore.backdrop.current
        let stats = ProfileStats.local()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    Button { picker = .backdrop } label: {
                        ProfileBackdropView(ref: backdrop).frame(height: 180).frame(maxWidth: .infinity).clipped()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cambiar fondo de perfil")
                    HStack(alignment: .bottom, spacing: 12) {
                        Button { picker = .avatar } label: { AvatarView(ref: avatar, size: 84) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cambiar foto de perfil")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username).font(.title3.bold()).foregroundColor(.white)
                            Button {
                                UIPasteboard.general.string = account.plixUserIdLabel
                                router.showToast("ID copiado")
                            } label: {
                                Label("ID \(account.plixUserIdLabel)", systemImage: "doc.on.doc").font(.caption)
                            }
                            .foregroundColor(.plixText)
                        }
                    }
                    .padding(16)
                    .offset(y: 30)
                }
                .padding(.bottom, 30)

                VStack(alignment: .leading, spacing: 8) {
                    Text(ProfileBioStore.text.isEmpty ? "¡Hola! Estoy viendo películas y series en PLIX 🍿" : ProfileBioStore.text)
                        .font(.subheadline).foregroundColor(.plixMuted)
                    Button("Editar descripción") {
                        bioDraft = ProfileBioStore.text
                        editingBio = true
                    }
                    .font(.footnote)
                }
                .padding(.horizontal, 16)

                section("Información de cuenta") {
                    infoRow("Nombre de usuario", account.username)
                    infoRow("Amigos", friendsCount.map(String.init) ?? "—")
                    HStack {
                        infoRow("PIN", showPin ? (Keychain.get("pin") ?? "No disponible") : "••••")
                        Button(showPin ? "Ocultar PIN" : "Mostrar PIN") { showPin.toggle() }.font(.footnote)
                    }
                    infoRow("Nube", account.syncLabel)
                    if SessionStore.lastBackupMs > 0 {
                        infoRow("Último respaldo", Date(timeIntervalSince1970: Double(SessionStore.lastBackupMs) / 1000)
                            .formatted(date: .abbreviated, time: .shortened))
                    }
                }

                section("Stickers del chat") {
                    let selected = StickerStore.selected
                    Text(selected.isEmpty ? "Elegí hasta 20 stickers para el chat de sala"
                         : "\(selected.count) / \(StickerStore.maxSelected) stickers seleccionados")
                        .font(.footnote).foregroundColor(.plixMuted)
                    if !selected.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(selected, id: \.self) { key in
                                    RemoteImage(url: StickerCatalog.url(for: key), contentMode: .fit).frame(width: 56, height: 56)
                                }
                            }
                        }
                    }
                    Button("Seleccionar stickers") { showStickers = true }.buttonStyle(PlixButtonStyle(filled: false))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mis estadísticas").font(.headline).foregroundColor(.plixText).padding(.horizontal, 16)
                    StatsGrid(stats: stats)
                }

                VStack(spacing: 10) {
                    Button(saving ? "Guardando…" : "Guardar cambios") { save() }
                        .buttonStyle(PlixButtonStyle())
                        .disabled(saving)
                    Button("Usar otra cuenta", role: .destructive) { confirmSignOut = true }
                        .buttonStyle(PlixButtonStyle(filled: false))
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
        }
        .task { friendsCount = (try? await FriendsService.listFriends())?.count }
        .sheet(isPresented: $editingBio) { BioEditor(text: $bioDraft) { saveBio() } }
        .sheet(item: $picker) { kind in ProfileImagePicker(kind: kind) }
        .sheet(isPresented: $showStickers) { StickerPickerView() }
        .confirmationDialog("¿Cerrar sesión en este iPhone? Se borrarán los datos respaldados de este dispositivo; seguirán en la nube.",
                            isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Usar otra cuenta", role: .destructive) { account.signOut() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundColor(.plixText)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.plixMuted)
            Text(value).font(.subheadline).foregroundColor(.plixText).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveBio() {
        ProfileBioStore.save(bioDraft)
        editingBio = false
        Task { await PublicProfileService.publishQuietly() }
    }

    private func save() {
        saving = true
        Task {
            do {
                try await account.saveNow()
                await PublicProfileService.publishQuietly()
                router.showToast("Cambios guardados")
            } catch {
                router.showToast(error.localizedDescription)
            }
            saving = false
        }
    }
}

extension ProfileImageKind: Identifiable {
    var id: String { field }
}

struct BioEditor: View {
    @Binding var text: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Los demás la verán en tu perfil").font(.footnote).foregroundColor(.plixMuted)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 140)
                    .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: text) { value in
                        if value.count > ProfileBioStore.maxLength { text = String(value.prefix(ProfileBioStore.maxLength)) }
                    }
                Text("\(text.count) / \(ProfileBioStore.maxLength)").font(.caption).foregroundColor(.plixMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Spacer()
            }
            .padding(16)
            .background(Color.plixBackground.ignoresSafeArea())
            .navigationTitle("Tu descripción")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: onSave) }
            }
        }
    }
}

struct ProfileImagePicker: View {
    let kind: ProfileImageKind
    @EnvironmentObject private var account: AccountManager
    @Environment(\.dismiss) private var dismiss
    @State private var sections: [ImagePackSection] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingView(message: "Cargando imágenes…")
                } else if failed {
                    MessageView(icon: "wifi.exclamationmark", message: "No se pudieron cargar las imágenes.", actionTitle: "Reintentar") {
                        Task { await load(force: true) }
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(sections) { section in
                                Text(section.title).font(.headline).foregroundColor(.plixText).padding(.horizontal, 16)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                                         count: kind == .avatar ? 4 : 2), spacing: 10) {
                                    ForEach(section.items, id: \.self) { ref in
                                        Button { choose(ref) } label: { thumbnail(ref) }.buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Color.plixBackground.ignoresSafeArea())
            .navigationTitle(kind == .avatar ? "Foto de perfil" : "Fondo de perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .task { await load(force: false) }
        }
    }

    @ViewBuilder
    private func thumbnail(_ ref: AvatarRef) -> some View {
        if kind == .avatar {
            AvatarView(ref: ref, size: 72)
        } else if ImageRepo.isVideo(ref) {
            ZStack {
                Color.plixSurfaceLight
                Image(systemName: "play.rectangle.fill").font(.title).foregroundColor(.plixMuted)
                Text(ref.id).font(.caption2).foregroundColor(.plixMuted).frame(maxHeight: .infinity, alignment: .bottom).padding(4)
            }
            .frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RemoteImage(url: ImageRepo.backdropURL(ref)).frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func load(force: Bool) async {
        loading = true
        failed = false
        do {
            sections = kind == .avatar
                ? try await ImageCatalogRepository.shared.avatarSections(force: force)
                : try await ImageCatalogRepository.shared.backdropSections(force: force)
            failed = sections.isEmpty
        } catch {
            failed = true
        }
        loading = false
    }

    private func choose(_ ref: AvatarRef) {
        kind.store.save(ref)
        account.pushProfileImage(kind)
        Task { await PublicProfileService.publishQuietly() }
        dismiss()
    }
}

struct StickerPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var all: [String] = []
    @State private var selected: [String] = StickerStore.selected
    @State private var loading = true
    @State private var failed = false
    @State private var warning: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingView(message: "Cargando stickers…")
                } else if failed {
                    MessageView(icon: "wifi.exclamationmark", message: "No se pudieron cargar los stickers", actionTitle: "Reintentar") {
                        Task { await load(force: true) }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(all, id: \.self) { key in
                                Button { toggle(key) } label: {
                                    RemoteImage(url: StickerCatalog.url(for: key), contentMode: .fit)
                                        .frame(height: 76)
                                        .padding(4)
                                        .background(selected.contains(key) ? Color.plixPrimary.opacity(0.35) : Color.plixSurface,
                                                    in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(alignment: .topTrailing) {
                                            if selected.contains(key) {
                                                Image(systemName: "checkmark.circle.fill").foregroundColor(.plixPrimary).padding(4)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(selected.contains(key) ? "Sticker seleccionado" : "Sticker")
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let warning { Text(warning).font(.caption).foregroundColor(.orange) }
                    Text("\(selected.count) / \(StickerStore.maxSelected) seleccionados").font(.caption).foregroundColor(.plixMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
                .background(Color.plixBackgroundDeep)
            }
            .background(Color.plixBackground.ignoresSafeArea())
            .navigationTitle("Seleccionar stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        StickerStore.save(selected)
                        dismiss()
                    }
                }
            }
            .task { await load(force: false) }
        }
    }

    private func toggle(_ key: String) {
        if let index = selected.firstIndex(of: key) {
            selected.remove(at: index)
            warning = nil
        } else if selected.count >= StickerStore.maxSelected {
            warning = "Máximo 20 stickers"
        } else {
            selected.append(key)
        }
    }

    private func load(force: Bool) async {
        loading = true
        failed = false
        do {
            all = try await ImageCatalogRepository.shared.stickers(force: force)
            failed = all.isEmpty
        } catch {
            failed = true
        }
        loading = false
    }
}

// MARK: Logros

struct AchievementsView: View {
    @EnvironmentObject private var achievements: AchievementManager
    @StateObject private var watcher = PrefsWatcher([AchievementStore.name])

    var body: some View {
        let list = achievements.snapshot()
        let unlocked = list.filter(\.unlocked).count
        let percent = list.isEmpty ? 0 : unlocked * 100 / list.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mis logros").font(.title2.bold()).foregroundColor(.plixText)
                    Text("🏆 \(unlocked) / \(list.count) desbloqueados").foregroundColor(.plixText)
                    ProgressView(value: Double(percent), total: 100).tint(.plixPrimary)
                    Text("\(percent)% completado").font(.caption).foregroundColor(.plixMuted)
                }
                .padding(16)
                .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 16))

                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    let items = list.filter { $0.category == category }
                    if !items.isEmpty {
                        Text("\(category.emoji) \(category.title)").font(.headline).foregroundColor(.plixText)
                        ForEach(items) { AchievementRow(achievement: $0) }
                    }
                }
            }
            .padding(16)
            .id(watcher.revision)
        }
    }
}

struct AchievementRow: View {
    let achievement: Achievement

    var body: some View {
        let hidden = achievement.secret && !achievement.unlocked
        HStack(alignment: .top, spacing: 12) {
            Text(hidden ? "🔒" : achievement.emoji).font(.largeTitle)
                .opacity(achievement.unlocked ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 4) {
                Text(hidden ? "???" : achievement.name).font(.subheadline.weight(.semibold)).foregroundColor(.plixText)
                Text(hidden ? "🔒 Secreto" : achievement.description).font(.caption).foregroundColor(.plixMuted)
                if achievement.unlocked {
                    Text("✓ DESBLOQUEADO").font(.caption2.bold()).foregroundColor(.green)
                    if achievement.unlockedAtMs > 0 {
                        Text(Date(timeIntervalSince1970: Double(achievement.unlockedAtMs) / 1000).formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundColor(.plixMuted)
                    }
                } else if !hidden && achievement.required > 1 {
                    ProgressView(value: Double(min(achievement.progress, achievement.required)), total: Double(achievement.required))
                        .tint(.plixPrimary)
                    Text("Progreso: \(min(achievement.progress, achievement.required)) / \(achievement.required)")
                        .font(.caption2).foregroundColor(.plixMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.plixSurface.opacity(achievement.unlocked ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: Diseño

struct DesignView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var watcher = PrefsWatcher([HeaderLogoStore.name, AchievementStore.name])

    var body: some View {
        let lzUnlocked = AchievementStore.isUnlocked("lz_play")
        let active = HeaderLogoStore.selected
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Logos").font(.title2.bold()).foregroundColor(.plixText)
                Text("Desliza y elige el logo activo del header.").font(.footnote).foregroundColor(.plixMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        logoCard(id: HeaderLogoStore.defaultLogo, title: "Por defecto", active: active) {
                            HStack(spacing: 2) {
                                Text("PLIX").font(.system(size: 30, weight: .black)).foregroundColor(.plixText)
                                Text("Lz").font(.system(size: 30, weight: .black)).foregroundColor(.plixPrimary)
                            }
                        }
                        if lzUnlocked {
                            logoCard(id: HeaderLogoStore.lzPlay, title: "Logo LzPlay", active: active) {
                                BundleImage(name: "logo_lzplay.png").frame(height: 40)
                            }
                        }
                    }
                }
                if !lzUnlocked {
                    Text("Desbloquea logros secretos para descubrir más logos.").font(.footnote).foregroundColor(.plixMuted)
                }
            }
            .padding(16)
            .id(watcher.revision)
        }
    }

    private func logoCard<Content: View>(id: String, title: String, active: String, @ViewBuilder content: () -> Content) -> some View {
        Button {
            HeaderLogoStore.select(id)
            router.showToast("Logo aplicado al header")
        } label: {
            VStack(spacing: 10) {
                content().frame(width: 200, height: 90)
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.plixText)
                if active == id { Text("Logo activo").font(.caption).foregroundColor(.plixPrimary) }
            }
            .padding(14)
            .background(Color.plixSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(active == id ? Color.plixPrimary : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
