import Foundation
import LocalAuthentication

final class LockManager: ObservableObject {
    @Published var isLocked: Bool

    init() {
        isLocked = UserDefaults.standard.bool(forKey: AppSettings.Keys.biometricLock)
    }

    func lockIfNeeded(enabled: Bool) {
        if enabled { isLocked = true }
    }

    @MainActor
    func unlock() async {
        let context = LAContext()
        var error: NSError?
        // Face ID / Touch ID con código del iPhone como respaldo
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                localizedReason: "Desbloquear Odysseus") {
                isLocked = false
            }
        } catch {
            // Cancelado o fallido: sigue bloqueado
        }
    }
}
