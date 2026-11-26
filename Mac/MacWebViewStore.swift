import AppKit
import WebKit

/// Dueño del WKWebView en macOS: navegación, errores, diálogos JS, subidas y descargas.
@MainActor
final class MacWebViewStore: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var isLoading = false
    @Published var loadError: String?
    @Published var title = "Odysseus"

    private var baseURL: URL?
    private var pendingDownloads: [ObjectIdentifier: URL] = [:]
    private var titleObservation: NSKeyValueObservation?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // cookies de sesión persistentes
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15 OdysseusMac/1.0"

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true                  // clic derecho > Inspeccionar elemento

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
            let newTitle = webView.title ?? ""
            Task { @MainActor in
                self?.title = newTitle.isEmpty ? "Odysseus" : newTitle
            }
        }
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

    private func isInternal(_ url: URL) -> Bool {
        guard let host = url.host else { return true }
        return host == baseURL?.host
    }

    private func uniqueDownloadURL(for filename: String) -> URL {
        let fm = FileManager.default
        let folder = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var index = 1
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}

// MARK: - Navegación

extension MacWebViewStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        guard let url = navigationAction.request.url else { return .allow }

        let webSchemes: Set<String> = ["http", "https", "about", "blob", "data"]
        if let scheme = url.scheme?.lowercased(), !webSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        // Enlaces externos → navegador por defecto
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame ?? true,
           !isInternal(url) {
            NSWorkspace.shared.open(url)
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

// MARK: - UI (ventanas nuevas, alert/confirm/prompt, selector de archivos, micrófono)

extension MacWebViewStore: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Aceptar")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    // <input type="file">: en macOS hay que mostrar el panel a mano
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }

    func webView(_ webView: WKWebView,
                 decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        origin.host == baseURL?.host ? .grant : .prompt
    }
}

// MARK: - Descargas → ~/Descargas y se muestran en el Finder

extension MacWebViewStore: WKDownloadDelegate {
    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let destination = uniqueDownloadURL(for: suggestedFilename)
        pendingDownloads[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = pendingDownloads.removeValue(forKey: ObjectIdentifier(download)) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        pendingDownloads.removeValue(forKey: ObjectIdentifier(download))
    }
}
