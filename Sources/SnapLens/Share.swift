import Foundation

/// Compartilhamento por link público (servidor PHP em `server/`).

enum ShareExpiry: Int, CaseIterable, Identifiable {
    case h1 = 3600, d1 = 86400, d7 = 604800, d30 = 2592000, never = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .h1: return L("1 hora")
        case .d1: return L("1 dia")
        case .d7: return L("7 dias")
        case .d30: return L("30 dias")
        case .never: return L("Sem expirar")
        }
    }
}

enum ShareConfig {
    static let defaultServer = "https://lens.ribeiros.click"

    static var server: String {
        let s = UserDefaults.standard.string(forKey: "share.server") ?? ""
        return (s.isEmpty ? defaultServer : s).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
    static var once: Bool { UserDefaults.standard.bool(forKey: "share.once") }
    static var expiry: ShareExpiry {
        guard UserDefaults.standard.object(forKey: "share.expiry") != nil,
              let e = ShareExpiry(rawValue: UserDefaults.standard.integer(forKey: "share.expiry")) else { return .d7 }
        return e
    }
}

struct ShareResult: Decodable {
    let id: String
    let url: String
    let expires_at: Double?
    let delete_token: String
    let once: Bool?
}

enum ShareClient {
    static func upload(data: Data, expiry: ShareExpiry, once: Bool) async throws -> ShareResult {
        let boundary = "SnapLens-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("expires", String(expiry.rawValue))
        field("once", once ? "1" : "0")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"screenshot.png\"\r\nContent-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = request(path: "/api/upload")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let json = try await send(req)
        return try JSONDecoder().decode(ShareResult.self, from: json)
    }

    static func revoke(id: String, token: String) async throws {
        var req = request(path: "/api/delete")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "token": token])
        _ = try await send(req)
    }

    private static func request(path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: ShareConfig.server + path)!, timeoutInterval: 60)
        r.httpMethod = "POST"
        return r
    }

    private static func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let msg = obj?["error"] as? String ?? "HTTP \(status)"
            throw AIError(message: L("Compartilhar: %@", msg))
        }
        return data
    }
}

func expiryText(_ date: Date?) -> String {
    guard let date else { return L("sem expirar") }
    let secs = date.timeIntervalSinceNow
    if secs <= 0 { return L("expirado") }
    if secs < 3600 { return L("expira em %@ min", String(max(1, Int(secs / 60)))) }
    if secs < 86400 * 2 { return L("expira em %@ h", String(Int((secs / 3600).rounded()))) }
    return L("expira em %@ dias", String(Int((secs / 86400).rounded())))
}
