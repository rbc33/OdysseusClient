import SwiftUI
import WebKit

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Dueño del WKWebView: navegación, errores, diálogos JS y descargas.
@MainActor
final class WebViewStore: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var isLoading = false
    @Published var loadError: String?
    @Published var sharedFile: SharedFile?

    private var baseURL: URL?
    private var pendingDownloads: [ObjectIdentifier: URL] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // cookies de sesión persistentes
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "OdysseusiOS/1.0"

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true                  // Safari > Desarrollo, para depurar
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
    }

    func load(_ url: URL) {
        baseURL = url
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        loadError = nil
        if webView.url == nil || webView.url?.host != baseURL?.host, let base = baseURL {
            webView.load(URLRequest(url: base))
        } else {
            webView.reload()
        }
    }

    func clearSessionData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                               modifiedSince: .distantPast)
        reload()
    }

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        reload()
        sender.endRefreshing()
    }

    private func isInternal(_ url: URL) -> Bool {
        guard let host = url.host else { return true }
        return host == baseURL?.host
    }

    private func topViewController() -> UIViewController? {
        var top = webView.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Navegación

extension WebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard let url = navigationAction.request.url else { return .allow }

        // mailto:, tel:, etc.
        let webSchemes: Set<String> = ["http", "https", "about", "blob", "data"]
        if let scheme = url.scheme?.lowercased(), !webSchemes.contains(scheme) {
            UIApplication.shared.open(url)
            return .cancel
        }
        // Enlaces externos (fuentes de deep research, etc.) → Safari
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame ?? true,
           !isInternal(url) {
            UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !navigationResponse.canShowMIMEType { return .download }
        if let http = navigationResponse.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        loadError = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // interrumpido por una descarga
        loadError = error.localizedDescription
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - UI (ventanas nuevas, alert/confirm/prompt, micrófono)

extension WebViewStore: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        guard let presenter = topViewController() else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in cont.resume() })
            presenter.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        guard let presenter = topViewController() else { return false }
        return await withCheckedContinuation { cont in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in cont.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in cont.resume(returning: true) })
            presenter.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        guard let presenter = topViewController() else { return nil }
        return await withCheckedContinuation { cont in
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in cont.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in
                cont.resume(returning: alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        origin.host == baseURL?.host ? .grant : .prompt
    }
}

// MARK: - Descargas (exportar documentos, imágenes de la galería…)

extension WebViewStore: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = dir.appendingPathComponent(suggestedFilename)
        pendingDownloads[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = pendingDownloads.removeValue(forKey: ObjectIdentifier(download)) {
            sharedFile = SharedFile(url: url)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pendingDownloads.removeValue(forKey: ObjectIdentifier(download))
    }
}
