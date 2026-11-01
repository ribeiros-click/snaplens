import Foundation
import ServiceManagement

/// "Iniciar com o macOS" via SMAppService (aparece em Ajustes do Sistema → Geral → Itens de Início).
enum LoginItem {
    private static let autoKey = "loginItem.autoEnabled"

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isOn: Bool { status == .enabled || status == .requiresApproval }

    /// O macOS só aceita registrar de forma confiável um app instalado em /Applications (ou ~/Applications).
    static var isInstalled: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Na primeira execução a partir de /Applications, liga o início automático.
    /// Roda uma única vez: se o usuário desligar depois, a escolha dele é respeitada.
    static func enableOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: autoKey), isInstalled else { return }
        UserDefaults.standard.set(true, forKey: autoKey)
        guard status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
            Trace.log("login item: registrado automaticamente · status=\(status.rawValue)")
        } catch {
            Trace.log("login item: falha ao registrar · \(error.localizedDescription)")
        }
    }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        UserDefaults.standard.set(true, forKey: autoKey)
    }

    static func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
