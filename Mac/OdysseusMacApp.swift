import SwiftUI

@main
struct OdysseusMacApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var lock = LockManager()
    @StateObject private var store = MacWebViewStore()

    var body: some Scene {
        // Una sola ventana: el WKWebView (y su sesión) es único
        Window("Odysseus", id: "main") {
            MacRootView(store: store)
                .environmentObject(settings)
                .environmentObject(lock)
                .frame(minWidth: 700, minHeight: 500)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Navegación") {
                Button("Recargar") { store.reload() }
                    .keyboardShortcut("r")
                Button("Atrás") { store.webView.goBack() }
                    .keyboardShortcut("[")
                Button("Adelante") { store.webView.goForward() }
                    .keyboardShortcut("]")
                Divider()
                Button("Tamaño real") { store.webView.pageZoom = 1 }
                    .keyboardShortcut("0")
                Button("Ampliar") { store.webView.pageZoom = min(store.webView.pageZoom + 0.1, 3) }
                    .keyboardShortcut("+")
                Button("Reducir") { store.webView.pageZoom = max(store.webView.pageZoom - 0.1, 0.5) }
                    .keyboardShortcut("-")
            }
        }

        Settings {
            MacSettingsView(store: store)
                .environmentObject(settings)
                .environmentObject(lock)
        }
    }
}
