import Foundation

/// Backup automático da Biblioteca para o OneDrive / Google Drive: mão única (Mac → Drive).
/// Cada item novo vai para a pasta escolhida; "Enviar a Biblioteca agora" manda também os antigos.
/// Apagar na Biblioteca não apaga no Drive.
@MainActor
final class DriveBackup: ObservableObject {
    static let shared = DriveBackup()

    @Published private(set) var status = ""
    @Published private(set) var running = false
    private var rerun = false
    private var timer: Timer?

    // MARK: Preferências

    private static let ud = UserDefaults.standard

    /// Drive de destino; nil = backup desligado (ou Drive desconectado).
    static var drive: CloudDrive? {
        get {
            guard let d = CloudDrive(rawValue: ud.string(forKey: "backup.drive") ?? ""),
                  CloudDrive.visible.contains(d), d.isConnected else { return nil }
            return d
        }
        set {
            ud.set(newValue?.rawValue ?? "", forKey: "backup.drive")
            // Ao ligar, só o que for capturado daqui em diante entra sozinho; o resto, pelo botão.
            if newValue != nil, ud.object(forKey: "backup.since") == nil { ud.set(Date(), forKey: "backup.since") }
        }
    }
    static var images: Bool { ud.object(forKey: "backup.images") as? Bool ?? true }
    static var videos: Bool { ud.object(forKey: "backup.videos") as? Bool ?? true }
    static var texts: Bool { ud.object(forKey: "backup.texts") as? Bool ?? true }
    private static var since: Date {
        get { ud.object(forKey: "backup.since") as? Date ?? Date() }
        set { ud.set(newValue, forKey: "backup.since") }
    }

    // MARK: Ciclo

    func start() {
        NotificationCenter.default.addObserver(forName: Store.inserted, object: Store.shared, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.run() }
        }
        // Tenta de novo o que ficou pendente (sem rede, Mac dormindo…) a cada 15 minutos.
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.run() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.run()
        }
    }

    /// Envia os itens pendentes. `all`: inclui os anteriores à ativação do backup.
    func run(all: Bool = false) {
        guard let drive = Self.drive else { status = ""; return }
        if all { Self.since = .distantPast }
        if running { rerun = true; return }
        running = true
        Task { @MainActor in
            defer { running = false }
            repeat {
                rerun = false
                await process(drive)
            } while rerun && Self.drive == drive
        }
    }

    private func pending(_ drive: CloudDrive) -> [Item] {
        let since = Self.since
        return Store.shared.items.filter { item in
            guard item.date >= since, item.backups?[drive.rawValue] == nil else { return false }
            if item.kind.isImage { return Self.images }
            if item.kind == .video { return Self.videos }
            return Self.texts && !(item.text ?? "").isEmpty
        }
        .reversed() // mais antigos primeiro
    }

    private func process(_ drive: CloudDrive) async {
        let items = pending(drive)
        guard !items.isEmpty else { status = L("Backup em dia"); return }
        for (n, item) in items.enumerated() {
            guard Self.drive == drive else { return }
            status = L("Enviando %@ de %@…", String(n + 1), String(items.count))
            do {
                guard let p = payload(for: item) else { continue }
                let r = try await CloudClient.uploadFile(drive, data: p.data, filename: p.name, mime: p.mime)
                // O item pode ter mudado (link compartilhado, apagado) enquanto o envio rodava.
                guard var current = Store.shared.items.first(where: { $0.id == item.id }) else { continue }
                current.backups = (current.backups ?? [:]).merging([drive.rawValue: r.id]) { _, new in new }
                Store.shared.update(current)
            } catch {
                Trace.log("backup \(drive.rawValue) ERRO: \(error.localizedDescription)")
                status = L("Backup pausado: %@", error.localizedDescription)
                return // tenta de novo no próximo item novo ou em 15 minutos
            }
        }
        status = L("Backup em dia")
    }

    private func payload(for item: Item) -> (data: Data, name: String, mime: String)? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = "SnapLens " + f.string(from: item.date)
        if item.kind.isText {
            guard let text = item.text, !text.isEmpty else { return nil }
            let label: String
            switch item.kind {
            case .ocr: label = "OCR"
            case .ai: label = "IA"
            default: label = "Texto"
            }
            return (Data(text.utf8), "\(stamp) \(label).txt", "text/plain; charset=utf-8")
        }
        guard let url = Store.shared.url(for: item),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if item.kind == .video { return (data, "\(stamp).\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)", "video/mp4") }
        return (data, "\(stamp).png", "image/png")
    }
}
