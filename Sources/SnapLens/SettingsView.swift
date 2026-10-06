import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("activeProvider") private var active = ""
    @AppStorage("rec.system") private var recSystem = true
    @AppStorage("rec.mic") private var recMic = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Geral") {
                Toggle("Iniciar com o macOS", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            launchAtLogin = on
                            loginError = nil
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            loginError = "Não foi possível alterar: \(error.localizedDescription). Mova o app para /Applications e tente de novo."
                        }
                    }))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section("Atalhos globais") {
                ForEach(ShortcutAction.allCases) { ShortcutRow(action: $0) }
                Text("Clique no atalho e pressione a nova combinação (precisa incluir ⌘, ⌃ ou ⌥).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Gravação de vídeo") {
                Toggle("Gravar áudio do sistema", isOn: $recSystem)
                Toggle("Gravar microfone", isOn: $recMic)
                Text("Grava a tela inteira onde está o mouse, em MP4. Com os dois desligados, o vídeo fica sem áudio. Os vídeos vão para a Biblioteca.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ShareSection()
            Section("Provedor de IA") {
                Picker("Provedor ativo", selection: $active) {
                    Text("Nativo (Apple Vision, offline)").tag("")
                    ForEach(Provider.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Text("“Descrever com IA” usa o provedor ativo. Sem provedor (ou sem chave configurada), usa o modo nativo. O OCR de texto sempre roda localmente com o Vision.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Provider.allCases) { p in
                ProviderSection(provider: p, isActive: active == p.rawValue) {
                    if active.isEmpty { active = p.rawValue }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 900)
    }
}

private struct ShareSection: View {
    @AppStorage("share.server") private var server = ""
    @AppStorage("share.expiry") private var expiry = ShareExpiry.d7.rawValue
    @State private var key = ""
    @State private var status: String?
    @State private var testing = false

    var body: some View {
        Section("Compartilhar por link público") {
            TextField("Servidor", text: $server, prompt: Text(ShareConfig.defaultServer))
            SecureField("Chave de upload", text: $key)
                .onChange(of: key) { _, v in Keychain.set(v.trimmingCharacters(in: .whitespacesAndNewlines), account: "share.key") }
            Picker("Validade padrão do link", selection: $expiry) {
                ForEach(ShareExpiry.allCases) { Text($0.title).tag($0.rawValue) }
            }
            HStack {
                Button(testing ? "Testando…" : "Testar conexão") {
                    testing = true
                    Task {
                        do { status = "✓ " + (try await ShareClient.ping()) }
                        catch { status = "✗ " + error.localizedDescription }
                        testing = false
                    }
                }
                .disabled(testing || key.isEmpty)
                if let status { Text(status).font(.caption).foregroundStyle(status.hasPrefix("✓") ? .green : .red) }
            }
            Text("O botão “link” no overlay e na Biblioteca envia a imagem ao servidor e copia a URL. Links expiram sozinhos e podem ser revogados na Biblioteca. A chave fica no Keychain; ela está em server/config.php do projeto.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { key = ShareConfig.key }
    }
}

private struct ProviderSection: View {
    let provider: Provider
    let isActive: Bool
    var onKeySaved: () -> Void
    @State private var key = ""
    @AppStorage private var model: String
    @AppStorage private var base: String

    init(provider: Provider, isActive: Bool, onKeySaved: @escaping () -> Void) {
        self.provider = provider
        self.isActive = isActive
        self.onKeySaved = onKeySaved
        _model = AppStorage(wrappedValue: "", "model.\(provider.rawValue)")
        _base = AppStorage(wrappedValue: "", "base.\(provider.rawValue)")
    }

    var body: some View {
        Section(provider.name + (isActive ? "  ✓ ativo" : "")) {
            SecureField(provider.needsKey ? "API key" : "API key (opcional)", text: $key)
                .onSubmit(save)
                .onChange(of: key) { _, _ in save() }
            TextField("Modelo", text: $model, prompt: Text(provider.defaultModel.isEmpty ? "ex.: llava, gpt-4o…" : provider.defaultModel))
            TextField("URL base", text: $base, prompt: Text(provider.defaultBase))
            Text(provider.hint).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { key = provider.apiKey }
    }

    private func save() {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: "key.\(provider.rawValue)")
        if !key.isEmpty { onKeySaved() }
    }
}
