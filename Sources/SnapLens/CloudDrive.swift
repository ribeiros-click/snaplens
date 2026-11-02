import AppKit
import CryptoKit
import Network

/// Destino do compartilhamento: servidor SnapLens (padrão), OneDrive ou Google Drive.
/// Nos Drives, a imagem vai para a pasta "SnapLens" da conta do usuário e recebe um link de leitura público.
enum ShareDestination: String, CaseIterable, Identifiable {
    case server, onedrive, gdrive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .server: return L("Servidor SnapLens")
        case .onedrive: return "OneDrive"
        case .gdrive: return "Google Drive"
        }
    }

    var drive: CloudDrive? { CloudDrive(rawValue: rawValue) }

    /// Destinos utilizáveis agora (o servidor sempre; os Drives só se conectados).
    static var available: [ShareDestination] {
        allCases.filter { d in d.drive.map { CloudDrive.visible.contains($0) && $0.isConnected } ?? true }
    }

    static var current: ShareDestination {
        get {
            let d = ShareDestination(rawValue: UserDefaults.standard.string(forKey: "share.destination") ?? "") ?? .server
            return available.contains(d) ? d : .server
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "share.destination") }
    }
}

enum CloudDrive: String, CaseIterable, Identifiable {
    case onedrive, gdrive
    var id: String { rawValue }
    var name: String { self == .onedrive ? "OneDrive" : "Google Drive" }

    /// Drives exibidos no app. O OneDrive está pronto no código, mas oculto por enquanto:
    /// para reativá-lo, basta voltar a incluir `.onedrive` aqui.
    static let visible: [CloudDrive] = [.gdrive]

    // MARK: Configuração OAuth
    // IDs vêm do Info.plist (gravados pelo build.sh a partir de variáveis de ambiente) ou de Ajustes → avançado.

    var clientID: String { config(plist: self == .onedrive ? "SnapLensOneDriveClientID" : "SnapLensGoogleClientID", defaults: "cloud.\(rawValue).clientId") }
    /// O Google exige o "client secret" mesmo em apps de desktop (não é tratado como segredo; o PKCE protege o fluxo).
    var clientSecret: String { self == .gdrive ? config(plist: "SnapLensGoogleClientSecret", defaults: "cloud.gdrive.clientSecret") : "" }
    var isConfigured: Bool { !clientID.isEmpty && (self == .onedrive || !clientSecret.isEmpty) }
    /// Chave de API do Google, usada só pelo seletor de pastas (Google Picker).
    var apiKey: String { self == .gdrive ? config(plist: "SnapLensGoogleAPIKey", defaults: "cloud.gdrive.apiKey") : "" }
    /// Número do projeto do Google (o prefixo do ID do cliente), exigido pelo Google Picker.
    fileprivate var projectNumber: String { String(clientID.prefix { $0.isNumber }) }
    /// O OneDrive navega pelas pastas dentro do app; o Google precisa da chave de API para abrir o seletor.
    var canPickFolder: Bool { isConnected && (self == .onedrive || !apiKey.isEmpty) }

    // MARK: Pasta de destino

    private var folderKey: String { "cloud.\(rawValue).folder.chosen" }

    /// Pasta escolhida pelo usuário; nil = pasta "SnapLens" criada pelo app na raiz.
    var folder: DriveFolder? {
        get { UserDefaults.standard.data(forKey: folderKey).flatMap { try? JSONDecoder().decode(DriveFolder.self, from: $0) } }
        nonmutating set {
            if let newValue, let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: folderKey) }
            else { UserDefaults.standard.removeObject(forKey: folderKey) }
        }
    }
    var folderDisplay: String { folder?.name ?? CloudClient.folderName }

    private func config(plist: String, defaults: String) -> String {
        let custom = (UserDefaults.standard.string(forKey: defaults) ?? "").trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty { return custom }
        return (Bundle.main.object(forInfoDictionaryKey: plist) as? String ?? "").trimmingCharacters(in: .whitespaces)
    }

    fileprivate var authorizeURL: String {
        self == .onedrive ? "https://login.microsoftonline.com/common/oauth2/v2.0/authorize" : "https://accounts.google.com/o/oauth2/v2/auth"
    }
    fileprivate var tokenURL: String {
        self == .onedrive ? "https://login.microsoftonline.com/common/oauth2/v2.0/token" : "https://oauth2.googleapis.com/token"
    }
    /// Escopos mínimos: OneDrive lê/grava os arquivos do usuário; Google só vê os arquivos criados pelo próprio SnapLens.
    fileprivate var scope: String {
        self == .onedrive ? "Files.ReadWrite offline_access" : "https://www.googleapis.com/auth/drive.file"
    }

    // MARK: Estado da conta

    private var refreshKey: String { "cloud.\(rawValue).refresh" }
    private var accountKey: String { "cloud.\(rawValue).account" }

    var isConnected: Bool { !(Keychain.get(refreshKey) ?? "").isEmpty }
    var accountName: String { UserDefaults.standard.string(forKey: accountKey) ?? "" }

    fileprivate func save(refresh: String) { Keychain.set(refresh, account: refreshKey) }
    fileprivate var refreshToken: String? { Keychain.get(refreshKey).flatMap { $0.isEmpty ? nil : $0 } }
    fileprivate func save(account: String) { UserDefaults.standard.set(account, forKey: accountKey) }

    func disconnect() {
        Keychain.set("", account: refreshKey)
        UserDefaults.standard.removeObject(forKey: accountKey)
        folder = nil
        Task { await TokenCache.shared.clear(self) }
    }
}

struct CloudUpload {
    let id: String
    let url: String
}

struct DriveFolder: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: Cliente

enum CloudClient {
    static let folderName = "SnapLens"

    /// Abre o login no navegador, recebe o código no loopback e guarda o refresh token no Keychain.
    @discardableResult
    static func connect(_ d: CloudDrive) async throws -> String {
        guard d.isConfigured else { throw cloudError(L("%@ não está configurado neste build.", d.name)) }
        let receiver = LoopbackReceiver()
        let port = try await receiver.start()
        defer { receiver.stop() }
        let redirect = "http://localhost:\(port)"
        let verifier = randomURLSafe(48)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = randomURLSafe(16)

        var c = URLComponents(string: d.authorizeURL)!
        var query: [URLQueryItem] = [
            .init(name: "client_id", value: d.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "scope", value: d.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: d == .gdrive ? "consent" : "select_account"),
        ]
        if d == .gdrive { query.append(.init(name: "access_type", value: "offline")) }
        c.queryItems = query
        let loginURL = c.url!
        await MainActor.run { _ = NSWorkspace.shared.open(loginURL) }

        let reply = try await receiver.waitForCallback(timeout: 300)
        let items = Dictionary(reply.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        if let err = items["error"] { throw cloudError(items["error_description"] ?? err) }
        guard items["state"] == state, let code = items["code"], !code.isEmpty else { throw cloudError(L("Resposta de login inválida.")) }

        var form = ["client_id": d.clientID, "grant_type": "authorization_code", "code": code,
                    "redirect_uri": redirect, "code_verifier": verifier, "scope": d.scope]
        if !d.clientSecret.isEmpty { form["client_secret"] = d.clientSecret }
        let tok = try await tokenRequest(d, form: form)
        guard let refresh = tok["refresh_token"] as? String else { throw cloudError(L("O provedor não devolveu um token de renovação.")) }
        d.save(refresh: refresh)
        if let access = tok["access_token"] as? String {
            await TokenCache.shared.put(d, token: access, expiresIn: tok["expires_in"] as? Double ?? 3000)
        }
        let name = (try? await accountName(d)) ?? ""
        d.save(account: name)
        Trace.log("cloud: \(d.rawValue) conectado")
        return name
    }

    /// Envia para o Drive e cria um link de leitura público (compartilhar).
    static func upload(_ d: CloudDrive, data: Data, filename: String, expires: Date?) async throws -> CloudUpload {
        let file = try await uploadFile(d, data: data, filename: filename, mime: "image/png")
        switch d {
        case .onedrive: return try await oneDriveLink(id: file.id, expires: expires)
        case .gdrive: return try await googleLink(id: file.id, webLink: file.webLink)
        }
    }

    /// Envia um arquivo para a pasta escolhida (ou "SnapLens"), sem link público. Usado também pelo backup.
    static func uploadFile(_ d: CloudDrive, data: Data, filename: String, mime: String) async throws -> (id: String, webLink: String?) {
        switch d {
        case .onedrive: return (try await oneDrivePut(data: data, filename: filename, mime: mime), nil)
        case .gdrive: return try await googlePut(data: data, filename: filename, mime: mime)
        }
    }

    /// Apaga o arquivo do Drive (o link deixa de funcionar). Arquivo já inexistente conta como sucesso.
    static func delete(_ d: CloudDrive, id: String) async throws {
        let url = d == .onedrive
            ? "https://graph.microsoft.com/v1.0/me/drive/items/\(id)"
            : "https://www.googleapis.com/drive/v3/files/\(id)"
        _ = try await api(d, method: "DELETE", url: url, allow404: true)
    }

    private static func deleteQuietly(_ d: CloudDrive, id: String) async {
        do { try await delete(d, id: id) } catch { Trace.log("cloud: não apagou \(id): \(error.localizedDescription)") }
    }

    // MARK: OneDrive (Microsoft Graph)

    private static func pathEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/:?#[]@!$&'()*+,;=")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Endereço do item `filename` dentro da pasta de destino, no formato `…/{pasta}:/{nome}:`.
    private static func oneDriveItemBase(_ filename: String) -> String {
        if let f = CloudDrive.onedrive.folder {
            return "https://graph.microsoft.com/v1.0/me/drive/items/\(f.id):/\(pathEncode(filename)):"
        }
        return "https://graph.microsoft.com/v1.0/me/drive/root:/\(pathEncode(folderName))/\(pathEncode(filename)):"
    }

    private static func oneDrivePut(data: Data, filename: String, mime: String) async throws -> String {
        let base = oneDriveItemBase(filename)
        // Envio simples aceita até 250 MB; acima disso (vídeos longos), sessão de upload em partes.
        if data.count <= 200 * 1024 * 1024 {
            let item = try await api(.onedrive, method: "PUT", url: base + "/content?@microsoft.graph.conflictBehavior=rename",
                                     body: data, contentType: mime)
            guard let id = item["id"] as? String else { throw cloudError(L("Resposta inesperada do %@.", "OneDrive")) }
            return id
        }
        let session = try await api(.onedrive, method: "POST", url: base + "/createUploadSession",
                                    body: try JSONSerialization.data(withJSONObject: ["item": ["@microsoft.graph.conflictBehavior": "rename"]]),
                                    contentType: "application/json")
        guard let uploadURL = (session["uploadUrl"] as? String).flatMap(URL.init(string:)) else {
            throw cloudError(L("Resposta inesperada do %@.", "OneDrive"))
        }
        let chunk = 32 * 320 * 1024 // 10 MiB, múltiplo de 320 KiB como o Graph exige
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunk, data.count)
            var req = URLRequest(url: uploadURL, timeoutInterval: 300)
            req.httpMethod = "PUT"
            req.setValue("bytes \(offset)-\(end - 1)/\(data.count)", forHTTPHeaderField: "Content-Range")
            let (body, resp) = try await URLSession.shared.upload(for: req, from: data.subdata(in: offset..<end))
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw cloudError(errorMessage(body, status: status), drive: .onedrive) }
            if status == 200 || status == 201 {
                let item = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                if let id = item?["id"] as? String { return id }
            }
            offset = end
        }
        throw cloudError(L("Resposta inesperada do %@.", "OneDrive"))
    }

    private static func oneDriveLink(id: String, expires: Date?) async throws -> CloudUpload {
        // Link anônimo com validade; contas pessoais não aceitam validade e algumas empresas bloqueiam links anônimos.
        let iso = expires.map { ISO8601DateFormatter().string(from: $0) }
        var attempts: [[String: Any]] = []
        if let iso { attempts.append(["type": "view", "scope": "anonymous", "expirationDateTime": iso]) }
        attempts.append(["type": "view", "scope": "anonymous"])
        attempts.append(["type": "view", "scope": "organization"])
        var lastError: Error?
        for body in attempts {
            do {
                let r = try await api(.onedrive, method: "POST", url: "https://graph.microsoft.com/v1.0/me/drive/items/\(id)/createLink",
                                      body: try JSONSerialization.data(withJSONObject: body), contentType: "application/json")
                if let link = (r["link"] as? [String: Any])?["webUrl"] as? String {
                    if body["scope"] as? String == "organization" { Trace.log("cloud: onedrive só permitiu link da organização") }
                    return CloudUpload(id: id, url: link)
                }
            } catch { lastError = error }
        }
        await deleteQuietly(.onedrive, id: id) // sem link, não deixa o arquivo órfão no Drive
        throw lastError ?? cloudError(L("Resposta inesperada do %@.", "OneDrive"))
    }

    /// Subpastas de uma pasta do OneDrive (nil = raiz), para o navegador de pastas em Ajustes.
    static func oneDriveFolders(in parent: DriveFolder?) async throws -> [DriveFolder] {
        let base = parent.map { "https://graph.microsoft.com/v1.0/me/drive/items/\($0.id)/children" }
            ?? "https://graph.microsoft.com/v1.0/me/drive/root/children"
        var next: String? = base + "?$select=id,name,folder&$top=200"
        var result: [DriveFolder] = []
        while let url = next {
            let r = try await api(.onedrive, method: "GET", url: url)
            for v in r["value"] as? [[String: Any]] ?? [] where v["folder"] != nil {
                if let id = v["id"] as? String, let name = v["name"] as? String { result.append(DriveFolder(id: id, name: name)) }
            }
            next = r["@odata.nextLink"] as? String
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Google Drive (API v3)

    /// Pasta de destino: a escolhida no seletor do Google ou a "SnapLens" criada pelo app.
    private static func googleTarget() async throws -> String {
        if let f = CloudDrive.gdrive.folder { return f.id }
        return try await googleFolder()
    }

    private static func googleFolder() async throws -> String {
        let key = "cloud.gdrive.folder"
        if let cached = UserDefaults.standard.string(forKey: key), !cached.isEmpty,
           let f = try? await api(.gdrive, method: "GET", url: "https://www.googleapis.com/drive/v3/files/\(cached)?fields=id,trashed"),
           f["trashed"] as? Bool != true {
            return cached
        }
        // Com o escopo drive.file, a busca só enxerga pastas criadas pelo próprio SnapLens.
        var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        c.queryItems = [.init(name: "q", value: "name='\(folderName)' and mimeType='application/vnd.google-apps.folder' and trashed=false"),
                        .init(name: "fields", value: "files(id)"), .init(name: "spaces", value: "drive")]
        let found = try await api(.gdrive, method: "GET", url: c.url!.absoluteString)
        if let id = ((found["files"] as? [[String: Any]])?.first)?["id"] as? String {
            UserDefaults.standard.set(id, forKey: key)
            return id
        }
        let created = try await api(.gdrive, method: "POST", url: "https://www.googleapis.com/drive/v3/files?fields=id",
                                    body: try JSONSerialization.data(withJSONObject: ["name": folderName, "mimeType": "application/vnd.google-apps.folder"]),
                                    contentType: "application/json")
        guard let id = created["id"] as? String else { throw cloudError(L("Resposta inesperada do %@.", "Google Drive")) }
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    private static func googlePut(data: Data, filename: String, mime: String) async throws -> (id: String, webLink: String?) {
        let folder = try await googleTarget()
        let meta = try JSONSerialization.data(withJSONObject: ["name": filename, "parents": [folder]])
        let file: [String: Any]
        if data.count <= 5 * 1024 * 1024 {
            // Upload "multipart": metadados + conteúdo numa só requisição (limite de 5 MB).
            let boundary = "SnapLens-\(UUID().uuidString)"
            var body = Data()
            body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
            body.append(meta)
            body.append("\r\n--\(boundary)\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            file = try await api(.gdrive, method: "POST",
                                 url: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink",
                                 body: body, contentType: "multipart/related; boundary=\(boundary)")
        } else {
            // Upload "resumable" (vídeos): abre a sessão e envia o conteúdo num único PUT.
            let (_, resp) = try await send(.gdrive, method: "POST",
                                           url: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,webViewLink",
                                           body: meta, contentType: "application/json; charset=UTF-8",
                                           headers: ["X-Upload-Content-Type": mime, "X-Upload-Content-Length": String(data.count)])
            guard let location = resp.value(forHTTPHeaderField: "Location") else {
                throw cloudError(L("Resposta inesperada do %@.", "Google Drive"))
            }
            let (body, _) = try await send(.gdrive, method: "PUT", url: location, body: data, contentType: mime)
            file = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }
        guard let id = file["id"] as? String else { throw cloudError(L("Resposta inesperada do %@.", "Google Drive")) }
        return (id, file["webViewLink"] as? String)
    }

    private static func googleLink(id: String, webLink: String?) async throws -> CloudUpload {
        do {
            _ = try await api(.gdrive, method: "POST", url: "https://www.googleapis.com/drive/v3/files/\(id)/permissions",
                              body: try JSONSerialization.data(withJSONObject: ["role": "reader", "type": "anyone"]),
                              contentType: "application/json")
        } catch {
            await deleteQuietly(.gdrive, id: id) // ex.: domínio do Workspace bloqueia link público
            throw error
        }
        return CloudUpload(id: id, url: webLink ?? "https://drive.google.com/file/d/\(id)/view")
    }

    /// Abre o seletor de pastas do Google (Google Picker) no navegador. Escolher uma pasta lá dá ao SnapLens
    /// acesso só àquela pasta, sem pedir permissão para ver o Drive inteiro. Retorna nil se cancelado.
    static func pickGoogleFolder() async throws -> DriveFolder? {
        let d = CloudDrive.gdrive
        guard !d.apiKey.isEmpty else { throw cloudError(L("Falta a chave de API do Google (veja “avançado”).")) }
        let token = try await accessToken(d)
        let cfg: [String: String] = [
            "token": token, "key": d.apiKey, "app": d.projectNumber,
            "hl": L10n.code == "zh-Hans" ? "zh-CN" : L10n.code,
            "title": L("Escolha a pasta do SnapLens"),
            "ok": L("Pronto! Pode fechar esta aba e voltar ao SnapLens."),
            "cancel": L("Cancelado. Pode fechar esta aba."),
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: cfg), encoding: .utf8)!
            .replacingOccurrences(of: "</", with: "<\\/")
        let page = pickerPage(configJSON: json)
        let receiver = LoopbackReceiver { path, query in
            if path == "/" { return LoopbackResponse(html: page, result: nil) }
            if path == "/picked" { return LoopbackResponse(html: "ok", result: query) }
            return nil
        }
        let port = try await receiver.start()
        defer { receiver.stop() }
        let pageURL = URL(string: "http://localhost:\(port)/")!
        await MainActor.run { _ = NSWorkspace.shared.open(pageURL) }
        let reply = try await receiver.waitForCallback(timeout: 600)
        let items = Dictionary(reply.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let id = items["id"], !id.isEmpty else { return nil }
        return DriveFolder(id: id, name: items["name"].flatMap { $0.isEmpty ? nil : $0 } ?? "Google Drive")
    }

    private static func pickerPage(configJSON: String) -> String {
        """
        <!doctype html><meta charset=utf-8><title>SnapLens</title>
        <body style="font:16px -apple-system,'Segoe UI',sans-serif;text-align:center;padding-top:60px;color:#333">
        <h2>SnapLens</h2><p id=msg>…</p>
        <script>
        const CFG = \(configJSON);
        function done(q, text) {
          fetch('/picked?' + q).finally(() => { document.getElementById('msg').textContent = text; });
        }
        function onPick(data) {
          if (data.action === google.picker.Action.PICKED) {
            const d = data.docs[0];
            done('id=' + encodeURIComponent(d.id) + '&name=' + encodeURIComponent(d.name), CFG.ok);
          } else if (data.action === google.picker.Action.CANCEL) {
            done('cancel=1', CFG.cancel);
          }
        }
        function start() {
          const view = new google.picker.DocsView(google.picker.ViewId.FOLDERS)
            .setIncludeFolders(true).setSelectFolderEnabled(true)
            .setMimeTypes('application/vnd.google-apps.folder');
          new google.picker.PickerBuilder().addView(view)
            .setOAuthToken(CFG.token).setDeveloperKey(CFG.key).setAppId(CFG.app)
            .setLocale(CFG.hl).setTitle(CFG.title).setCallback(onPick)
            .build().setVisible(true);
        }
        </script>
        <script src="https://apis.google.com/js/api.js" onload="gapi.load('picker', start)"></script>
        """
    }

    // MARK: Conta

    private static func accountName(_ d: CloudDrive) async throws -> String {
        if d == .onedrive {
            let r = try await api(d, method: "GET", url: "https://graph.microsoft.com/v1.0/me/drive?$select=owner")
            let user = (r["owner"] as? [String: Any])?["user"] as? [String: Any]
            return user?["email"] as? String ?? user?["displayName"] as? String ?? ""
        }
        let r = try await api(d, method: "GET", url: "https://www.googleapis.com/drive/v3/about?fields=user(emailAddress,displayName)")
        let user = r["user"] as? [String: Any]
        return user?["emailAddress"] as? String ?? user?["displayName"] as? String ?? ""
    }

    // MARK: HTTP

    private static func api(_ d: CloudDrive, method: String, url: String, body: Data? = nil, contentType: String? = nil,
                            allow404: Bool = false) async throws -> [String: Any] {
        let (data, resp) = try await send(d, method: method, url: url, body: body, contentType: contentType, allow404: allow404)
        if allow404 && resp.statusCode == 404 { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Requisição autenticada; renova o token uma vez se o servidor responder 401.
    private static func send(_ d: CloudDrive, method: String, url: String, body: Data? = nil, contentType: String? = nil,
                             headers: [String: String] = [:], allow404: Bool = false, retried: Bool = false) async throws -> (Data, HTTPURLResponse) {
        let token = try await accessToken(d)
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: body.map { $0.count > 5_000_000 ? 900 : 120 } ?? 120)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp): (Data, URLResponse)
        if let body { (data, resp) = try await URLSession.shared.upload(for: req, from: body) }
        else { (data, resp) = try await URLSession.shared.data(for: req) }
        guard let http = resp as? HTTPURLResponse else { throw cloudError("HTTP 0", drive: d) }
        if http.statusCode == 401 && !retried {
            await TokenCache.shared.clear(d)
            return try await send(d, method: method, url: url, body: body, contentType: contentType, headers: headers, allow404: allow404, retried: true)
        }
        if allow404 && http.statusCode == 404 { return (data, http) }
        guard (200..<300).contains(http.statusCode) else { throw cloudError(errorMessage(data, status: http.statusCode), drive: d) }
        return (data, http)
    }

    private static func accessToken(_ d: CloudDrive) async throws -> String {
        if let t = await TokenCache.shared.get(d) { return t }
        guard let refresh = d.refreshToken else { throw cloudError(L("Conecte o %@ em Ajustes.", d.name)) }
        var form = ["client_id": d.clientID, "grant_type": "refresh_token", "refresh_token": refresh]
        if d == .onedrive { form["scope"] = d.scope }
        if !d.clientSecret.isEmpty { form["client_secret"] = d.clientSecret }
        // Só um 400/401 do servidor de login significa acesso revogado/expirado; rede e 5xx propagam como estão.
        let tok = try await tokenRequest(d, form: form, expiredMessage: L("A conexão com o %@ expirou. Conecte de novo em Ajustes.", d.name))
        guard let access = tok["access_token"] as? String else { throw cloudError(L("Resposta de login inválida.")) }
        if let newRefresh = tok["refresh_token"] as? String { d.save(refresh: newRefresh) }
        await TokenCache.shared.put(d, token: access, expiresIn: tok["expires_in"] as? Double ?? 3000)
        return access
    }

    private static func tokenRequest(_ d: CloudDrive, form: [String: String], expiredMessage: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: d.tokenURL)!, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if let expiredMessage, status == 400 || status == 401 { throw cloudError(expiredMessage) }
        guard (200..<300).contains(status) else { throw cloudError(errorMessage(data, status: status), drive: d) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func errorMessage(_ data: Data, status: Int) -> String {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let e = obj?["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let d = obj?["error_description"] as? String { return d }
        if let e = obj?["error"] as? String { return e }
        return "HTTP \(status)"
    }

    private static func cloudError(_ message: String, drive: CloudDrive? = nil) -> AIError {
        AIError(message: drive.map { "\($0.name): \(message)" } ?? message)
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64URL
    }
}

private actor TokenCache {
    static let shared = TokenCache()
    private var tokens: [CloudDrive: (token: String, until: Date)] = [:]

    func get(_ d: CloudDrive) -> String? {
        guard let t = tokens[d], t.until > Date() else { return nil }
        return t.token
    }
    func put(_ d: CloudDrive, token: String, expiresIn: Double) {
        tokens[d] = (token, Date().addingTimeInterval(max(60, expiresIn - 120)))
    }
    func clear(_ d: CloudDrive) { tokens[d] = nil }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: Receptor do redirecionamento OAuth (http://localhost:porta/)

struct LoopbackResponse {
    let html: String
    /// Não nil: encerra a espera com esta resposta.
    let result: [URLQueryItem]?
}

/// Servidor HTTP mínimo, só na interface de loopback: recebe o redirecionamento do login
/// ou serve a página do seletor de pastas do Google.
private final class LoopbackReceiver: @unchecked Sendable {
    typealias Route = @Sendable (_ path: String, _ query: [URLQueryItem]) -> LoopbackResponse?

    /// Padrão: qualquer `/?…` é o retorno do login OAuth.
    static let oauthRoute: Route = { path, query in
        guard path == "/", !query.isEmpty else { return nil }
        let html = "<!doctype html><meta charset=utf-8><title>SnapLens</title><body style='font:16px -apple-system,sans-serif;text-align:center;padding-top:80px'><h2>SnapLens ✓</h2><p>\(L("Pronto! Pode fechar esta aba e voltar ao SnapLens."))</p>"
        return LoopbackResponse(html: html, result: query)
    }

    private let route: Route
    init(route: @escaping Route = LoopbackReceiver.oauthRoute) { self.route = route }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "snaplens.oauth")
    private var callback: CheckedContinuation<[URLQueryItem], Error>?
    private var pending: Result<[URLQueryItem], Error>?
    private var finished = false

    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        listener = l
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            let once = ResumeOnce()
            l.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.claim() { cont.resume(returning: l.port?.rawValue ?? 0) }
                case .failed(let e): if once.claim() { cont.resume(throwing: e) }
                default: break
                }
            }
            l.start(queue: queue)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [URLQueryItem] {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                if let pending = self.pending { self.pending = nil; cont.resume(with: pending); return }
                self.callback = cont
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(AIError(message: L("Tempo de login esgotado."))))
                }
            }
        }
    }

    func stop() { queue.async { self.listener?.cancel(); self.listener = nil } }

    private func finish(_ result: Result<[URLQueryItem], Error>) {
        guard !finished else { return }
        finished = true
        guard let cb = callback else { pending = result; return }
        callback = nil
        cb.resume(with: result)
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            let comps = URLComponents(string: "http://localhost" + target)
            let response = comps.flatMap { self.route($0.path, $0.queryItems ?? []) }
            let body = Data((response?.html ?? "Not found").utf8)
            let head = "HTTP/1.1 \(response == nil ? "404 Not Found" : "200 OK")\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
            if let result = response?.result { self.queue.async { self.finish(.success(result)) } }
        }
    }
}

/// Garante que uma continuação seja retomada uma única vez (os callbacks rodam na fila do receptor).
private final class ResumeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
