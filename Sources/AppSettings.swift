import Foundation

final class AppSettings: ObservableObject {
    static let defaultServer = ""   // vacío: la primera vez se abren los ajustes

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Keys.serverURL) }
    }
    @Published var biometricLock: Bool {
        didSet { UserDefaults.standard.set(biometricLock, forKey: Keys.biometricLock) }
    }

    enum Keys {
        static let serverURL = "serverURL"
        static let biometricLock = "biometricLock"
    }

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: Keys.serverURL) ?? Self.defaultServer
        biometricLock = defaults.bool(forKey: Keys.biometricLock)
    }

    var url: URL? { Self.normalize(serverURL) }

    /// Acepta "servidor:7000", "100.x.y.z:7000" o una URL completa.
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }
}
