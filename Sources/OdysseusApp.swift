import SwiftUI

@main
struct OdysseusApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var lock = LockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(lock)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock.lockIfNeeded(enabled: settings.biometricLock)
            }
        }
    }
}
