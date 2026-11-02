import Foundation
import SystemConfiguration

/// Regras da sincronização, sem rede nem tela (testadas em SnapLensTests).
enum SyncPlan {
    struct Options {
        var images = true
        var videos = false
        var texts = true
    }

    /// Itens criados aqui, dentro da janela de dias e ainda não enviados.
    static func toUpload(_ items: [Item], cutoff: Date, options: Options) -> [Item] {
        items.filter { item in
            guard item.date >= cutoff, item.syncId == nil, item.device == nil else { return false }
            if item.kind.isImage { return options.images && item.file != nil }
            if item.kind == .video { return options.videos && item.file != nil }
            return options.texts && !(item.text ?? "").isEmpty
        }
        .sorted { $0.date < $1.date }
    }

    /// Metadados guardados em appProperties (cada chave+valor ≤ 124 bytes no Drive).
    static func props(for item: Item, deviceID: String, deviceName: String) -> [String: String] {
        var p: [String: String] = [
            "id": item.id.uuidString,
            "kind": item.kind.rawValue,
            "date": ISO8601DateFormatter().string(from: item.date),
            "device": deviceID,
            "deviceName": String(deviceName.prefix(60)),
        ]
        if let s = item.source, !s.isEmpty { p["source"] = String(s.prefix(60)) }
        if let d = item.duration { p["duration"] = String(format: "%.1f", d) }
        return p
    }

    /// Item local reconstruído a partir de um arquivo remoto; nil se já existe, é deste aparelho ou está fora da janela.
    static func incoming(props: [String: String], fileID: String, localIDs: Set<UUID>, deviceID: String, cutoff: Date) -> Item? {
        guard let raw = props["id"], let id = UUID(uuidString: raw), !localIDs.contains(id),
              props["device"] != deviceID,
              let kind = ItemKind(rawValue: props["kind"] ?? ""),
              let date = props["date"].flatMap(CloudClient.parseISO), date >= cutoff else { return nil }
        var item = Item(kind: kind)
        item.id = id
        item.date = date
        item.source = props["source"]
        item.duration = props["duration"].flatMap(Double.init)
        item.device = props["deviceName"] ?? "?"
        item.syncId = fileID
        if kind.isImage { item.file = id.uuidString + ".png" }
        if kind == .video { item.file = id.uuidString + ".mp4" }
        return item
    }
}

/// Sincroniza a Biblioteca dos últimos X dias entre os computadores conectados ao mesmo Google Drive.
/// Mão dupla: envia o que foi criado aqui e traz o que os outros enviaram. Apagar não se propaga.
@MainActor
final class LibrarySync: ObservableObject {
    static let shared = LibrarySync()

    @Published private(set) var status = ""
    @Published private(set) var running = false
    private var rerun = false
    private var timer: Timer?
    nonisolated private static let ud = UserDefaults.standard

    // MARK: Preferências

    nonisolated static var enabled: Bool {
        get { ud.bool(forKey: "sync.enabled") }
        set { ud.set(newValue, forKey: "sync.enabled") }
    }
    nonisolated static var days: Int {
        get { let d = ud.integer(forKey: "sync.days"); return d == 0 ? 7 : min(max(d, 1), 90) }
        set { ud.set(min(max(newValue, 1), 90), forKey: "sync.days") }
    }
    nonisolated static var options: SyncPlan.Options {
        SyncPlan.Options(images: ud.object(forKey: "sync.images") as? Bool ?? true,
                         videos: ud.object(forKey: "sync.videos") as? Bool ?? false,
                         texts: ud.object(forKey: "sync.texts") as? Bool ?? true)
    }
    /// Identificador fixo deste computador (não muda se o nome mudar).
    nonisolated static var deviceID: String {
        if let id = ud.string(forKey: "sync.deviceId") { return id }
        let id = UUID().uuidString
        ud.set(id, forKey: "sync.deviceId")
        return id
    }
    nonisolated static var deviceName: String {
        // Nome do Mac em Ajustes do Sistema → Geral → Sobre (leitura local, não consulta a rede como Host.current()).
        get { (ud.string(forKey: "sync.deviceName")).flatMap { $0.isEmpty ? nil : $0 }
                ?? (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac" }
        set { ud.set(newValue, forKey: "sync.deviceName") }
    }
    nonisolated static var isAvailable: Bool { enabled && CloudDrive.visible.contains(.gdrive) && CloudDrive.gdrive.isConnected }

    // MARK: Ciclo

    func start() {
        NotificationCenter.default.addObserver(forName: Store.inserted, object: Store.shared, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.run() }
        }
        // Traz o que os outros computadores enviaram a cada 5 minutos.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.run() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self.run()
        }
    }

    func run() {
        guard Self.isAvailable else { status = ""; return }
        if running { rerun = true; return }
        running = true
        Task { @MainActor in
            defer { running = false }
            repeat {
                rerun = false
                await cycle()
            } while rerun && Self.isAvailable
        }
    }

    private func cycle() async {
        let cutoff = Date().addingTimeInterval(-Double(Self.days) * 86400)
        let device = Self.deviceID
        do {
            // 1. Envia o que foi criado aqui.
            let up = SyncPlan.toUpload(Store.shared.items, cutoff: cutoff, options: Self.options)
            for (n, item) in up.enumerated() {
                status = L("Enviando %@ de %@…", String(n + 1), String(up.count))
                guard let payload = payload(for: item) else { continue }
                let id = try await CloudClient.syncUpload(data: payload.data, filename: payload.name, mime: payload.mime,
                                                          props: SyncPlan.props(for: item, deviceID: device, deviceName: Self.deviceName))
                guard var current = Store.shared.items.first(where: { $0.id == item.id }) else { continue }
                current.syncId = id
                Store.shared.update(current)
            }
            // 2. Traz o que veio dos outros.
            let remote = try await CloudClient.syncList(after: cutoff)
            let local = Set(Store.shared.items.map(\.id))
            let incoming = remote.compactMap { f in
                SyncPlan.incoming(props: f.props, fileID: f.id, localIDs: local, deviceID: device, cutoff: cutoff)
            }
            .filter { Self.options.images || !$0.kind.isImage }
            .filter { Self.options.videos || $0.kind != .video }
            .filter { Self.options.texts || !$0.kind.isText }
            for (n, var item) in incoming.enumerated() {
                status = L("Recebendo %@ de %@…", String(n + 1), String(incoming.count))
                let data = try await CloudClient.download(.gdrive, id: item.syncId ?? "")
                if item.kind.isText {
                    item.text = String(data: data, encoding: .utf8) ?? ""
                    Store.shared.importSynced(item, data: nil)
                } else {
                    Store.shared.importSynced(item, data: data)
                }
            }
            // 3. Apaga da pasta de sincronização o que este computador enviou e já saiu da janela.
            for old in try await CloudClient.syncList(before: cutoff, device: device) {
                try? await CloudClient.delete(.gdrive, id: old.id)
            }
            let f = DateFormatter()
            f.locale = L10n.locale
            f.timeStyle = .short
            status = L("Sincronizado às %@", f.string(from: Date()))
        } catch {
            Trace.log("sync ERRO: \(error.localizedDescription)")
            status = L("Sincronização pausada: %@", error.localizedDescription)
        }
    }

    private func payload(for item: Item) -> (data: Data, name: String, mime: String)? {
        let name = item.id.uuidString
        if item.kind.isText {
            guard let t = item.text, !t.isEmpty else { return nil }
            return (Data(t.utf8), name + ".txt", "text/plain; charset=utf-8")
        }
        guard let url = Store.shared.url(for: item), let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return item.kind == .video ? (data, name + ".mp4", "video/mp4") : (data, name + ".png", "image/png")
    }
}
