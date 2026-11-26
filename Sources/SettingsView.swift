import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var store: WebViewStore
    @Environment(\.dismiss) private var dismiss

    @State private var draftURL = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://servidor.tu-tailnet.ts.net", text: $draftURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Probar conexión")
                            if testing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(testing)
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Servidor")
                } footer: {
                    Text("URL https de `tailscale serve`, nombre MagicDNS (servidor:7000) o IP (100.x.y.z:7000).")
                }

                Section("Seguridad") {
                    Toggle("Bloquear con Face ID", isOn: $settings.biometricLock)
                }

                Section {
                    Button("Recargar") { store.reload(); dismiss() }
                    Button("Cerrar sesión y borrar datos", role: .destructive) { confirmClear = true }
                } footer: {
                    Text("Agita el iPhone en cualquier momento para abrir estos ajustes.")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(AppSettings.normalize(draftURL) == nil)
                }
            }
            .confirmationDialog("Se borrarán cookies y datos locales. Tendrás que volver a iniciar sesión.",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) {
                    Task { await store.clearSessionData(); dismiss() }
                }
            }
            .onAppear { draftURL = settings.serverURL }
        }
    }

    private func save() {
        guard let url = AppSettings.normalize(draftURL) else { return }
        let value = url.absoluteString
        if value == settings.serverURL {
            store.reload()                       // misma URL: forzar recarga
        } else {
            settings.serverURL = value           // dispara .task(id:) en RootView
        }
        dismiss()
    }

    private func testConnection() async {
        guard let url = AppSettings.normalize(draftURL) else {
            testResult = "URL no válida"
            return
        }
        testing = true
        defer { testing = false }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            testResult = "✅ Responde (HTTP \(code))"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}
