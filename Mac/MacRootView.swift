import SwiftUI
import WebKit

struct MacRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: LockManager
    @ObservedObject var store: MacWebViewStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .top) {
            MacWebViewContainer(webView: store.webView)

            if store.isLoading && store.webView.url == nil {
                ProgressView().padding(.top, 80)
            }

            if let error = store.loadError {
                MacConnectionErrorView(
                    message: error,
                    server: settings.serverURL,
                    retry: { store.reload() },
                    openSettings: { openSettings() }
                )
            }

            if lock.isLocked {
                MacLockView { Task { await lock.unlock() } }
            }
        }
        .navigationTitle(store.title)
        .task(id: settings.serverURL) {
            if let url = settings.url {
                store.load(url)
            } else {
                openSettings()
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
            lock.lockIfNeeded(enabled: settings.biometricLock)
        }
    }
}

struct MacWebViewContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct MacConnectionErrorView: View {
    let message: String
    let server: String
    let retry: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No se puede conectar con Odysseus")
                .font(.title3.bold())
            Text(server).font(.callout.monospaced()).foregroundStyle(.secondary)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("¿Está Tailscale activo y el contenedor levantado?")
                .font(.footnote)
            HStack {
                Button("Ajustes…", action: openSettings)
                Button("Reintentar", action: retry)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

struct MacLockView: View {
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 44))
            Text("Odysseus está bloqueado").font(.title3.bold())
            Button("Desbloquear", action: unlock)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .onAppear(perform: unlock)
    }
}
