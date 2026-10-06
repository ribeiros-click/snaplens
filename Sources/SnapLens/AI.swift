import AppKit
import Security
import ImageIO

// MARK: Keychain

enum Keychain {
    private static let service = "com.jjunior.snaplens"

    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: Providers

enum Provider: String, CaseIterable, Identifiable {
    case anthropic, openai, deepseek, custom
    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .custom: return "Personalizado (compatível com OpenAI)"
        }
    }
    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .custom: return "Personalizado"
        }
    }
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-5-5"
        case .openai: return "gpt-4o-mini"
        case .deepseek: return "deepseek-chat"
        case .custom: return ""
        }
    }
    var defaultBase: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openai: return "https://api.openai.com/v1"
        case .deepseek: return "https://api.deepseek.com"
        case .custom: return "http://localhost:11434/v1"
        }
    }
    var hint: String {
        switch self {
        case .anthropic: return "Suporta imagens."
        case .openai: return "Suporta imagens (use um modelo com visão, ex.: gpt-4o)."
        case .deepseek: return "Atenção: os modelos da API oficial do DeepSeek podem não aceitar imagens. Se der erro, use outro provedor ou um modelo com visão."
        case .custom: return "Ollama (http://localhost:11434/v1), OpenRouter, Groq, Gemini (…/v1beta/openai) etc. A chave é opcional."
        }
    }
    var needsKey: Bool { self != .custom }

    var apiKey: String { Keychain.get("key.\(rawValue)") ?? "" }
    var model: String {
        let m = UserDefaults.standard.string(forKey: "model.\(rawValue)") ?? ""
        return m.isEmpty ? defaultModel : m
    }
    var baseURL: String {
        let b = UserDefaults.standard.string(forKey: "base.\(rawValue)") ?? ""
        return (b.isEmpty ? defaultBase : b).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }
    var isConfigured: Bool { (!needsKey || !apiKey.isEmpty) && !model.isEmpty }

    /// Provedor ativo; nil = nativo (Apple Vision).
    static var active: Provider? {
        guard let raw = UserDefaults.standard.string(forKey: "activeProvider"),
              let p = Provider(rawValue: raw), p.isConfigured else { return nil }
        return p
    }
}

// MARK: Client

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum AIClient {
    static let prompt = """
    Descreva esta imagem de forma clara e objetiva, em português do Brasil. \
    Se houver texto visível, transcreva-o fielmente em uma seção final chamada "Texto na imagem".
    """

    static func describe(imageURL: URL, provider: Provider) async throws -> String {
        guard let png = scaledPNG(imageURL, maxSize: 1568) else { throw AIError(message: "Não consegui ler a imagem.") }
        let b64 = png.base64EncodedString()
        let req: URLRequest
        switch provider {
        case .anthropic: req = try anthropicRequest(provider, b64)
        default: req = try openAIRequest(provider, b64)
        }
        return try await send(req, provider: provider)
    }

    static func translate(_ text: String, to language: String, provider: Provider) async throws -> String {
        let instruction = "Traduza o texto a seguir para \(language). Responda apenas com a tradução, sem comentários.\n\n\(text)"
        var req: URLRequest
        if provider == .anthropic {
            req = try makeRequest(provider.baseURL + "/v1/messages", body: [
                "model": provider.model, "max_tokens": 4000,
                "messages": [["role": "user", "content": instruction]],
            ])
            req.setValue(provider.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            req = try makeRequest(provider.baseURL + "/chat/completions", body: [
                "model": provider.model, "max_tokens": 4000,
                "messages": [["role": "user", "content": instruction]],
            ])
            if !provider.apiKey.isEmpty { req.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization") }
        }
        return try await send(req, provider: provider)
    }

    private static func send(_ req: URLRequest, provider: Provider) async throws -> String {
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
            throw AIError(message: "\(provider.shortName) respondeu \(status): \(msg)")
        }
        let text: String?
        if provider == .anthropic {
            text = (json?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            text = ((json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            throw AIError(message: "Resposta vazia do provedor.")
        }
        return t
    }

    private static func makeRequest(_ urlString: String, body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw AIError(message: "URL inválida: \(urlString)") }
        var r = URLRequest(url: url, timeoutInterval: 90)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    private static func anthropicRequest(_ p: Provider, _ b64: String) throws -> URLRequest {
        var r = try makeRequest(p.baseURL + "/v1/messages", body: [
            "model": p.model, "max_tokens": 1500,
            "messages": [["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": b64]],
                ["type": "text", "text": prompt],
            ]]],
        ])
        r.setValue(p.apiKey, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return r
    }

    private static func openAIRequest(_ p: Provider, _ b64: String) throws -> URLRequest {
        var r = try makeRequest(p.baseURL + "/chat/completions", body: [
            "model": p.model, "max_tokens": 1500,
            "messages": [["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(b64)"]],
            ]]],
        ])
        if !p.apiKey.isEmpty { r.setValue("Bearer \(p.apiKey)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private static func scaledPNG(_ url: URL, maxSize: Int) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxSize]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
