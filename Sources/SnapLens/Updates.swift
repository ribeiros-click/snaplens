import AppKit

/// Aviso de versão nova: consulta a última release pública no GitHub ao abrir e uma vez por dia.
/// Não baixa nada sozinho; mostra o item "SnapLens X disponível" no menu e um aviso uma vez por versão.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let changed = Notification.Name("SnapLensUpdateChanged")
    static let releasesAPI = URL(string: "https://api.github.com/repos/ribeiros-click/snaplens/releases/latest")!

    /// Versão nova encontrada (nil = está atualizado ou ainda não verificou).
    private(set) var available: (version: String, url: URL)?
    private var timer: Timer?

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "updates.check") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updates.check") }
    }

    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.check() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await self.check()
        }
    }

    /// `manual`: chamado pelo menu; avisa também quando já está na versão mais recente ou dá erro.
    func check(manual: Bool = false) async {
        guard manual || Self.enabled else { return }
        var req = URLRequest(url: Self.releasesAPI, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("SnapLens/\(Self.currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String,
                  let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { throw URLError(.badServerResponse) }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isNewer(latest, than: Self.currentVersion) {
                available = (latest, page)
                Trace.log("update: \(latest) disponível (atual \(Self.currentVersion))")
                let key = "updates.notified"
                if manual || UserDefaults.standard.string(forKey: key) != latest {
                    UserDefaults.standard.set(latest, forKey: key)
                    Toast.show(L("SnapLens %@ disponível — veja no menu", latest), symbol: "arrow.down.circle")
                }
            } else {
                available = nil
                if manual { Toast.show(L("Você está na versão mais recente (%@)", Self.currentVersion), symbol: "checkmark.circle") }
            }
            NotificationCenter.default.post(name: Self.changed, object: nil)
        } catch {
            Trace.log("update: falha ao verificar: \(error.localizedDescription)")
            if manual { Toast.show(L("Não foi possível verificar atualizações"), symbol: "exclamationmark.triangle.fill") }
        }
    }

    /// Compara versões "1.10" > "1.9" número a número (não como texto).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
