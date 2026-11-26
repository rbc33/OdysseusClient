import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var store: MacWebViewStore

    @State private var draftURL = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                TextField("URL", text: $draftURL, prompt: Text("https://rictow.tu-tailnet.ts.net"))
                    .autocorrectionDisabled()
                    .onSubmit(save)
                HStack {
                    Button("Probar conexión") { Task { await testConnection() } }
                        .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Guardar", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(AppSettings.normalize(draftURL) == nil)
                }
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Servidor")
            } footer: {
                Text("MagicDNS (rictow:7000), IP de Tailscale o LAN (100.x.y.z:7000) o la URL https de `tailscale serve`.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Seguridad") {
                Toggle("Bloquear con Touch ID al abrir y al bloquear la pantalla", isOn: $settings.biometricLock)
            }

            Section {
                Button("Cerrar sesión y borrar datos…", role: .destructive) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .confirmationDialog("Se borrarán cookies y datos locales. Tendrás que volver a iniciar sesión.",
                            isPresented: $confirmClear) {
            Button("Borrar", role: .destructive) {
                Task { await store.clearSessionData() }
            }
        }
        .onAppear { draftURL = settings.serverURL }
    }

    private func save() {
        guard let url = AppSettings.normalize(draftURL) else { return }
        let value = url.absoluteString
        draftURL = value
        if value == settings.serverURL {
            store.reload()
        } else {
            settings.serverURL = value           // dispara .task(id:) en MacRootView
        }
        testResult = "Guardado"
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
