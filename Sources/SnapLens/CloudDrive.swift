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
    static var available: [ShareDestination] { allCases.filter { $0.drive?.isConnected ?? true } }

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

    // MARK: Configuração OAuth
    // IDs vêm do Info.plist (gravados pelo build.sh a partir de variáveis de ambiente) ou de Ajustes → avançado.

    var clientID: String { config(plist: self == .onedrive ? "SnapLensOneDriveClientID" : "SnapLensGoogleClientID", defaults: "cloud.\(rawValue).clientId") }
    /// O Google exige o "client secret" mesmo em apps de desktop (não é tratado como segredo; o PKCE protege o fluxo).
    var clientSecret: String { self == .gdrive ? config(plist: "SnapLensGoogleClientSecret", defaults: "cloud.gdrive.clientSecret") : "" }
    var isConfigured: Bool { !clientID.isEmpty && (self == .onedrive || !clientSecret.isEmpty) }

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
        Task { await TokenCache.shared.clear(self) }
    }
}

struct CloudUpload {
    let id: String
    let url: String
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

    static func upload(_ d: CloudDrive, data: Data, filename: String, expires: Date?) async throws -> CloudUpload {
        switch d {
        case .onedrive: return try await oneDriveUpload(data: data, filename: filename, expires: expires)
        case .gdrive: return try await googleUpload(data: data, filename: filename)
        }
    }

    /// Apaga o arquivo do Drive (o link deixa de funcionar). Arquivo já inexistente conta como sucesso.
    static func delete(_ d: CloudDrive, id: String) async throws {
        let url = d == .onedrive
            ? "https://graph.microsoft.com/v1.0/me/drive/items/\(id)"
            : "https://www.googleapis.com/drive/v3/files/\(id)"
        _ = try await api(d, method: "DELETE", url: url, allow404: true)
    }

    // MARK: OneDrive (Microsoft Graph)

    private static func oneDriveUpload(data: Data, filename: String, expires: Date?) async throws -> CloudUpload {
        let path = "\(folderName)/\(filename)".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        let item = try await api(.onedrive, method: "PUT",
                                 url: "https://graph.microsoft.com/v1.0/me/drive/root:/\(path):/content?@microsoft.graph.conflictBehavior=rename",
                                 body: data, contentType: "image/png")
        guard let id = item["id"] as? String else { throw cloudError(L("Resposta inesperada do %@.", "OneDrive")) }

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
        throw lastError ?? cloudError(L("Resposta inesperada do %@.", "OneDrive"))
    }

    // MARK: Google Drive (API v3)

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

    private static func googleUpload(data: Data, filename: String) async throws -> CloudUpload {
        let folder = try await googleFolder()
        let boundary = "SnapLens-\(UUID().uuidString)"
        var body = Data()
        let meta = try JSONSerialization.data(withJSONObject: ["name": filename, "parents": [folder]])
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(meta)
        body.append("\r\n--\(boundary)\r\nContent-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let file = try await api(.gdrive, method: "POST",
                                 url: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink",
                                 body: body, contentType: "multipart/related; boundary=\(boundary)")
        guard let id = file["id"] as? String else { throw cloudError(L("Resposta inesperada do %@.", "Google Drive")) }
        _ = try await api(.gdrive, method: "POST", url: "https://www.googleapis.com/drive/v3/files/\(id)/permissions",
                          body: try JSONSerialization.data(withJSONObject: ["role": "reader", "type": "anyone"]),
                          contentType: "application/json")
        let link = file["webViewLink"] as? String ?? "https://drive.google.com/file/d/\(id)/view"
        return CloudUpload(id: id, url: link)
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
                            allow404: Bool = false, retried: Bool = false) async throws -> [String: Any] {
        let token = try await accessToken(d)
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 120)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 && !retried {
            await TokenCache.shared.clear(d)
            return try await api(d, method: method, url: url, body: body, contentType: contentType, allow404: allow404, retried: true)
        }
        if allow404 && status == 404 { return [:] }
        guard (200..<300).contains(status) else { throw cloudError(errorMessage(data, status: status), drive: d) }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func accessToken(_ d: CloudDrive) async throws -> String {
        if let t = await TokenCache.shared.get(d) { return t }
        guard let refresh = d.refreshToken else { throw cloudError(L("Conecte o %@ em Ajustes.", d.name)) }
        var form = ["client_id": d.clientID, "grant_type": "refresh_token", "refresh_token": refresh]
        if d == .onedrive { form["scope"] = d.scope }
        if !d.clientSecret.isEmpty { form["client_secret"] = d.clientSecret }
        let tok: [String: Any]
        do { tok = try await tokenRequest(d, form: form) } catch {
            throw cloudError(L("A conexão com o %@ expirou. Conecte de novo em Ajustes.", d.name))
        }
        guard let access = tok["access_token"] as? String else { throw cloudError(L("Resposta de login inválida.")) }
        if let newRefresh = tok["refresh_token"] as? String { d.save(refresh: newRefresh) }
        await TokenCache.shared.put(d, token: access, expiresIn: tok["expires_in"] as? Double ?? 3000)
        return access
    }

    private static func tokenRequest(_ d: CloudDrive, form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: d.tokenURL)!, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
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

/// Servidor HTTP mínimo, só na interface de loopback, que espera o redirecionamento do login.
private final class LoopbackReceiver: @unchecked Sendable {
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
            let isCallback = comps?.path == "/" && comps?.queryItems?.isEmpty == false
            let html = isCallback
                ? "<!doctype html><meta charset=utf-8><title>SnapLens</title><body style='font:16px -apple-system,sans-serif;text-align:center;padding-top:80px'><h2>SnapLens ✓</h2><p>\(L("Pronto! Pode fechar esta aba e voltar ao SnapLens."))</p>"
                : "Not found"
            let body = Data(html.utf8)
            let head = "HTTP/1.1 \(isCallback ? "200 OK" : "404 Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
            if isCallback { self.finish(.success(comps?.queryItems ?? [])) }
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
