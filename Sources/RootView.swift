import SwiftUI
import WebKit

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: LockManager
    @StateObject private var store = WebViewStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            WebViewContainer(webView: store.webView)

            if store.isLoading && store.webView.url == nil {
                ProgressView().padding(.top, 60)
            }

            if let error = store.loadError {
                ConnectionErrorView(
                    message: error,
                    server: settings.serverURL,
                    retry: { store.reload() },
                    openSettings: { showSettings = true }
                )
            }

            // Tapa el contenido en el selector de apps si el bloqueo está activo
            if settings.biometricLock && scenePhase != .active {
                PrivacyCover()
            }

            if lock.isLocked {
                LockView { Task { await lock.unlock() } }
            }
        }
        .task(id: settings.serverURL) {
            if let url = settings.url {
                store.load(url)
            } else {
                showSettings = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
        .sheet(item: $store.sharedFile) { file in
            ShareSheet(items: [file.url])
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ConnectionErrorView: View {
    let message: String
    let server: String
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No se puede conectar con Odysseus")
                .font(.headline)
            Text(server).font(.callout.monospaced()).foregroundStyle(.secondary)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("¿Está Tailscale activo en el iPhone y el contenedor levantado?")
                .font(.footnote).multilineTextAlignment(.center)
            HStack {
                Button("Ajustes", action: openSettings).buttonStyle(.bordered)
                Button("Reintentar", action: retry).buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 44))
            Text("Odysseus está bloqueado").font(.headline)
            Button("Desbloquear", action: unlock).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .ignoresSafeArea()
        .onAppear(perform: unlock)
    }
}

struct PrivacyCover: View {
    var body: some View {
        Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Agitar el iPhone abre los ajustes de la app
extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
