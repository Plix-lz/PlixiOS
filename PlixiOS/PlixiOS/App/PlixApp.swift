import AVFoundation
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// El reproductor habilita horizontal; el resto de la app queda en vertical.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        CloudConfig.configureIfPossible()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        UNUserNotificationCenter.current().delegate = self
        PrefsRegistry.shared.onBackedUpDataChanged = { _ in
            if SessionStore.isSignedIn { SessionStore.markLocalChange() }
        }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    static func setOrientation(_ mask: UIInterfaceOrientationMask) {
        orientationLock = mask
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

@main
struct PlixApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var router = AppRouter()
    @StateObject private var account = AccountManager.shared
    @StateObject private var achievements = AchievementManager.shared
    @StateObject private var network = NetworkMonitor.shared
    @StateObject private var watchParty = WatchPartySession.shared
    @State private var foregroundSince = Date()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(account)
                .environmentObject(achievements)
                .environmentObject(network)
                .environmentObject(watchParty)
                .preferredColorScheme(.dark)
                .tint(.plixPrimary)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                foregroundSince = Date()
                AchievementManager.shared.onAppOpened()
                AccountManager.shared.appDidBecomeActive()
                Task { await AccountManager.shared.startupSync() }
            case .background:
                recordUsage()
                AccountManager.shared.appDidEnterBackground()
            default:
                break
            }
        }
    }

    private func recordUsage() {
        let elapsed = Int64(Date().timeIntervalSince(foregroundSince) * 1000)
        AppUsageStore.add(elapsed, userKey: SessionStore.isSignedIn ? SessionStore.uid : "local")
        foregroundSince = Date()
    }
}

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Color.plixBackground.ignoresSafeArea()
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                MainView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}

struct SplashView: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 28) {
                BundleImage(name: "lzplay_splash_logo.png").frame(maxWidth: 220, maxHeight: 220)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(Color(hex: 0xE50914), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .background(Circle().stroke(Color(hex: 0xE50914, alpha: 0.18), lineWidth: 4))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            }
        }
        .onAppear { spin = true }
    }
}
