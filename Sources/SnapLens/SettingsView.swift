import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("rec.system") private var recSystem = true
    @AppStorage("rec.mic") private var recMic = false
    @State private var launchAtLogin = LoginItem.isOn
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    enum Tab: String { case general, shortcuts, recording, share, ai }
    @AppStorage("settings.tab") private var tab: Tab = .general

    var body: some View {
        TabView(selection: $tab) {
            Form { generalSections }.formStyle(.grouped)
                .tabItem { Label(L("Geral"), systemImage: "gearshape") }.tag(Tab.general)
            Form { shortcutSection }.formStyle(.grouped)
                .tabItem { Label(L("Atalhos"), systemImage: "keyboard") }.tag(Tab.shortcuts)
            Form { recordingSection }.formStyle(.grouped)
                .tabItem { Label(L("Gravação"), systemImage: "record.circle") }.tag(Tab.recording)
            Form { ShareSection() }.formStyle(.grouped)
                .tabItem { Label(L("Compartilhar"), systemImage: "link") }.tag(Tab.share)
            Form { AISection() }.formStyle(.grouped)
                .tabItem { Label(L("IA"), systemImage: "sparkles") }.tag(Tab.ai)
        }
        .padding(.top, 6)
        .frame(width: 560, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Volta dos Ajustes do Sistema: reflete a aprovação (ou remoção) feita lá.
            launchAtLogin = LoginItem.isOn
            loginStatus = LoginItem.status
        }
    }

    @ViewBuilder private var generalSections: some View {
        Section(L("Idioma")) {
            Picker(L("Idioma do app"), selection: Binding(get: { L10n.selection }, set: { L10n.selection = $0 })) {
                Text(L("Mesmo do sistema")).tag("system")
                ForEach(L10n.languages, id: \.code) { Text($0.name).tag($0.code) }
            }
        }
        Section(L("Geral")) {
            Toggle(L("Iniciar com o macOS"), isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    do {
                        try LoginItem.set(on)
                        loginError = nil
                    } catch {
                        loginError = L("Não foi possível alterar: %@. Mova o app para /Applications e tente de novo.", error.localizedDescription)
                    }
                    launchAtLogin = LoginItem.isOn
                    loginStatus = LoginItem.status
                }))
            if loginStatus == .requiresApproval {
                HStack {
                    Text(L("O macOS precisa da sua aprovação em Itens de Início."))
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(L("Abrir Ajustes do Sistema")) { LoginItem.openSystemSettings() }
                        .controlSize(.small)
                }
            } else if !LoginItem.isInstalled {
                Text(L("Para iniciar com o macOS, mova o SnapLens para a pasta Aplicativos."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
        }
    }

    private var shortcutSection: some View {
        Section(L("Atalhos globais")) {
            ForEach(ShortcutAction.allCases) { ShortcutRow(action: $0) }
            Text(L("Clique no atalho e pressione a nova combinação (precisa incluir ⌘, ⌃ ou ⌥)."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recordingSection: some View {
        Section(L("Gravação de vídeo")) {
            Toggle(L("Gravar áudio do sistema"), isOn: $recSystem)
            Toggle(L("Gravar microfone"), isOn: $recMic)
            Text(L("Grava a tela inteira onde está o mouse, em MP4. Com os dois desligados, o vídeo fica sem áudio. Os vídeos vão para a Biblioteca."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Aba IA: só os provedores adicionados aparecem (até 4); "Adicionar provedor" lista os que faltam.
private struct AISection: View {
    @AppStorage("activeProvider") private var active = ""
    @State private var added = Provider.added
    @State private var removing: Provider?

    var body: some View {
        Section(L("Provedor de IA")) {
            Picker(L("Provedor ativo"), selection: $active) {
                Text(L("Nativo (Apple Vision, offline)")).tag("")
                ForEach(added) { Text($0.name).tag($0.rawValue) }
            }
            Text(L("“Descrever com IA” usa o provedor ativo. Sem provedor (ou sem chave configurada), usa o modo nativo. O OCR de texto sempre roda localmente com o Vision."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Menu {
                    ForEach(Provider.allCases.filter { !added.contains($0) }) { p in
                        Button(p.name) { add(p) }
                    }
                } label: {
                    Label(L("Adicionar provedor"), systemImage: "plus")
                }
                .fixedSize()
                .disabled(added.count >= Provider.maxAdded || added.count == Provider.allCases.count)
                Spacer()
                Text(L("%@ de %@", String(added.count), String(Provider.maxAdded)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(L("Remover %@?", removing?.name ?? ""), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(L("Remover"), role: .destructive) {
                removing?.remove()
                added = Provider.added
                if !added.contains(where: { $0.rawValue == active }) { active = "" }
                removing = nil
            }
        } message: {
            Text(L("A chave de API, o modelo e a URL deste provedor serão apagados."))
        }
        ForEach(added) { p in
            ProviderSection(provider: p, isActive: active == p.rawValue, onKeySaved: {
                if active.isEmpty { active = p.rawValue }
            }, onRemove: { removing = p })
        }
    }

    private func add(_ p: Provider) {
        guard added.count < Provider.maxAdded, !added.contains(p) else { return }
        added.append(p)
        Provider.added = added
    }
}

private struct ShareSection: View {
    @AppStorage("share.server") private var server = ""

    var body: some View {
        Section(L("Compartilhar por link público")) {
            TextField(L("Servidor"), text: $server, prompt: Text(ShareConfig.defaultServer))
            Text(L("Ao clicar em “link” no overlay ou na Biblioteca, você escolhe a validade (ver uma vez, 1 dia, 5 dias, X dias ou nunca) antes do envio. Links são anônimos — nenhuma conta necessária. Guarde o token de exclusão para apagar um link fora do app."))
                .font(.caption).foregroundStyle(.secondary)
        }
        Section(L("Salvar no Google Drive")) {
            ForEach(CloudDrive.visible) { CloudDriveRow(drive: $0) }
            Text(L("Conecte uma conta para escolher, na hora de compartilhar, onde salvar a imagem. Ela vai para a pasta SnapLens do Drive e recebe um link de leitura público. O SnapLens só acessa os arquivos que ele mesmo cria (no Google Drive) e guarda o acesso no Keychain."))
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(L("Credenciais OAuth (avançado)")) {
                if CloudDrive.visible.contains(.onedrive) { TextField(L("OneDrive — ID do cliente"), text: $oneDriveID) }
                TextField(L("Google — ID do cliente"), text: $googleID)
                SecureField(L("Google — chave secreta do cliente"), text: $googleSecret)
                SecureField(L("Google — chave de API (seletor de pastas)"), text: $googleAPIKey)
                Text(L("Deixe em branco para usar as credenciais deste build. Preencha só se você registrou o seu próprio app na Microsoft ou no Google (redirecionamento: http://localhost)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        BackupSection()
    }

    @AppStorage("cloud.onedrive.clientId") private var oneDriveID = ""
    @AppStorage("cloud.gdrive.clientId") private var googleID = ""
    @AppStorage("cloud.gdrive.clientSecret") private var googleSecret = ""
    @AppStorage("cloud.gdrive.apiKey") private var googleAPIKey = ""
}

/// Backup automático da Biblioteca para um Drive conectado (mão única).
private struct BackupSection: View {
    @AppStorage("backup.drive") private var driveRaw = ""
    @AppStorage("backup.images") private var images = true
    @AppStorage("backup.videos") private var videos = true
    @AppStorage("backup.texts") private var texts = true
    @ObservedObject private var backup = DriveBackup.shared
    @State private var connected: [CloudDrive] = []

    var body: some View {
        Section(L("Backup automático da Biblioteca")) {
            Picker(L("Enviar para"), selection: Binding(
                get: { connected.contains { $0.rawValue == driveRaw } ? driveRaw : "" },
                set: { raw in
                    DriveBackup.drive = CloudDrive(rawValue: raw)
                    driveRaw = raw
                    backup.run()
                })) {
                Text(L("Desligado")).tag("")
                ForEach(connected) { Text($0.name).tag($0.rawValue) }
            }
            if let d = CloudDrive(rawValue: driveRaw), connected.contains(d) {
                Toggle(L("Screenshots e imagens"), isOn: $images)
                Toggle(L("Gravações de vídeo"), isOn: $videos)
                Toggle(L("Textos (OCR, IA e copiados)"), isOn: $texts)
                HStack {
                    Button(L("Enviar a Biblioteca agora")) { backup.run(all: true) }
                        .disabled(backup.running)
                    if backup.running { ProgressView().controlSize(.small) }
                    Spacer()
                    Text(backup.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(L("Pasta: %@. Cada captura nova vai sozinha para lá. É uma cópia de segurança: apagar na Biblioteca não apaga no Drive.", d.folderDisplay))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(connected.isEmpty
                     ? L("Conecte o Google Drive acima para ativar o backup.")
                     : L("Escolha um Drive para copiar sozinho cada captura nova, e a Biblioteca inteira quando quiser."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in refresh() }
    }

    private func refresh() {
        let now = CloudDrive.visible.filter(\.isConnected)
        if now != connected { connected = now }
    }
}

/// Navegador de pastas do OneDrive (Microsoft Graph), aberto por "Escolher…" em Ajustes.
private struct OneDriveFolderPicker: View {
    var onPick: (DriveFolder) -> Void
    var onCancel: () -> Void
    @State private var path: [DriveFolder] = []
    @State private var folders: [DriveFolder] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Escolha a pasta do OneDrive")).font(.headline)
            HStack(spacing: 6) {
                Button { path.removeLast(); load() } label: { Image(systemName: "chevron.left") }
                    .disabled(path.isEmpty || loading)
                Text((["OneDrive"] + path.map(\.name)).joined(separator: " › "))
                    .lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
            }
            ZStack {
                List(folders) { f in
                    Button { path.append(f); load() } label: {
                        Label(f.name, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if loading { ProgressView() }
                else if let errorText { Text(errorText).foregroundStyle(.red).padding() }
                else if folders.isEmpty { Text(L("Nenhuma subpasta")).foregroundStyle(.secondary) }
            }
            .frame(height: 260)
            HStack {
                Button(L("Cancelar"), role: .cancel) { onCancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Escolher esta pasta")) {
                    let name = (["OneDrive"] + path.map(\.name)).joined(separator: "/")
                    onPick(DriveFolder(id: path.last?.id ?? "root", name: name))
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(loading)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear(perform: load)
    }

    private func load() {
        loading = true
        errorText = nil
        let parent = path.last
        Task { @MainActor in
            do { folders = try await CloudClient.oneDriveFolders(in: parent) }
            catch { folders = []; errorText = error.localizedDescription }
            loading = false
        }
    }
}

private struct CloudDriveRow: View {
    let drive: CloudDrive
    @State private var connected = false
    @State private var account = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var folder = ""
    @State private var customFolder = false
    @State private var browsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: connected ? "checkmark.icloud.fill" : "icloud").foregroundStyle(connected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(drive.name)
                    if connected {
                        Text(account.isEmpty ? L("Conectado") : L("Conectado como %@", account))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !drive.isConfigured {
                        Text(L("Sem credenciais OAuth neste build (veja “avançado”)."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if connected {
                    Button(L("Desconectar")) { drive.disconnect(); refresh() }
                } else {
                    Button(L("Conectar…")) { connect() }.disabled(busy || !drive.isConfigured)
                }
            }
            if connected {
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(L("Pasta: %@", folder)).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if customFolder {
                        Button(L("Padrão")) { drive.folder = nil; refresh() }.controlSize(.small)
                            .help(L("Voltar para a pasta SnapLens criada pelo app"))
                    }
                    Button(L("Escolher…")) { chooseFolder() }.controlSize(.small)
                        .disabled(busy || !drive.canPickFolder)
                }
                if !drive.canPickFolder {
                    Text(L("Para escolher outra pasta, falta a chave de API do Google: cadastre o secret GOOGLE_API_KEY e gere um build novo, ou cole a chave em “Credenciais OAuth (avançado)”."))
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in refresh() }
        .sheet(isPresented: $browsing) {
            OneDriveFolderPicker(onPick: { f in
                drive.folder = f
                browsing = false
                refresh()
            }, onCancel: { browsing = false })
        }
    }

    private func refresh() {
        connected = drive.isConnected
        account = drive.accountName
        folder = drive.folderDisplay
        customFolder = drive.folder != nil
    }

    private func chooseFolder() {
        errorText = nil
        if drive == .onedrive { browsing = true; return }
        busy = true
        Task { @MainActor in
            do {
                if let f = try await CloudClient.pickGoogleFolder() { drive.folder = f }
                NSApp.activate(ignoringOtherApps: true)
            } catch { errorText = error.localizedDescription }
            busy = false
            refresh()
        }
    }

    private func connect() {
        busy = true
        errorText = nil
        Task { @MainActor in
            do {
                try await CloudClient.connect(drive)
                NSApp.activate(ignoringOtherApps: true)
            } catch { errorText = error.localizedDescription }
            busy = false
            refresh()
        }
    }
}

private struct ProviderSection: View {
    let provider: Provider
    let isActive: Bool
    var onKeySaved: () -> Void
    var onRemove: () -> Void
    @State private var key = ""
    @AppStorage private var model: String
    @AppStorage private var base: String

    init(provider: Provider, isActive: Bool, onKeySaved: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.provider = provider
        self.isActive = isActive
        self.onKeySaved = onKeySaved
        self.onRemove = onRemove
        _model = AppStorage(wrappedValue: "", "model.\(provider.rawValue)")
        _base = AppStorage(wrappedValue: "", "base.\(provider.rawValue)")
    }

    var body: some View {
        Section(provider.name + (isActive ? "  ✓ " + L("ativo") : "")) {
            SecureField(provider.needsKey ? "API key" : L("API key (opcional)"), text: $key)
                .onSubmit(save)
                .onChange(of: key) { _, _ in save() }
            TextField(L("Modelo"), text: $model, prompt: Text(provider.defaultModel.isEmpty ? L("ex.: llava, gpt-4o…") : provider.defaultModel))
            TextField(L("URL base"), text: $base, prompt: Text(provider.defaultBase))
            Text(provider.hint).font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive) { onRemove() } label: { Label(L("Remover"), systemImage: "trash") }
                .controlSize(.small)
        }
        .onAppear { key = provider.apiKey }
    }

    private func save() {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: "key.\(provider.rawValue)")
        if !key.isEmpty { onKeySaved() }
    }
}
