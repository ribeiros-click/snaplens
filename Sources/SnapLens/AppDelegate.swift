import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var historyWindow: NSWindow?
    private let store = Store.shared
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var clipTimer: Timer?
    private var overlay: CaptureOverlay?
    private var settingsWindow: NSWindow?
    private var shareWindow: NSWindow?
    private var shareOptionsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Trace.log("=== SnapLens iniciado · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · telas=\(NSScreen.screens.count)")
        for n in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Trace.log("app \(n == NSApplication.didBecomeActiveNotification ? "ATIVO" : "inativo") · overlayVisível=\(OverlayWindow.anyVisible)") }
            }
        }
        NSApp.applicationIconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        Keychain.set("", account: "share.key") // limpa chave de API legada; compartilhar não exige mais conta
        HangWatchdog.start()
        LoginItem.enableOnFirstRun()
        setupMenu()
        setupHotKeys()
        startClipboardMonitor()
        startDriveExpiry()
        DriveBackup.shared.start()
        NotificationCenter.default.addObserver(forName: Recorder.stateChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordingStateChanged() }
        }
        // Troca de idioma: refaz o menu e as janelas (que guardam textos já traduzidos).
        NotificationCenter.default.addObserver(forName: L10n.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildMenu()
                self.historyWindow?.close(); self.historyWindow = nil
                self.shareWindow?.close(); self.shareWindow = nil
                let wasOpen = self.settingsWindow?.isVisible ?? false
                self.settingsWindow?.close(); self.settingsWindow = nil
                if wasOpen { self.showSettings() }
            }
        }
    }

    // MARK: Gravação

    private var recTimer: Timer?

    @objc func toggleRecording() {
        Task {
            if Recorder.shared.isRecording {
                await Recorder.shared.stop()
            } else {
                Toast.dismiss()
                do {
                    try await Recorder.shared.start(screen: Capture.screenUnderMouse())
                    Toast.show(L("Gravando… use o atalho ou o menu para parar"), symbol: "record.circle")
                } catch {
                    let msg = (error as? Recorder.Failure)?.errorDescription ?? error.localizedDescription
                    Toast.show(msg, symbol: "exclamationmark.triangle.fill")
                    if case Recorder.Failure.noPermission = error {
                        CGRequestScreenCaptureAccess()
                    }
                }
            }
        }
    }

    private func recordingStateChanged() {
        rebuildMenu()
        let recording = Recorder.shared.isRecording
        let name = recording ? "record.circle.fill" : "viewfinder"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "SnapLens")
        if recording {
            statusItem.button?.image = img?.withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            statusItem.length = NSStatusItem.variableLength
            recTimer?.invalidate()
            recTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let start = Recorder.shared.startDate else { return }
                    self?.statusItem.button?.title = " " + formatDuration(Date().timeIntervalSince(start))
                }
            }
        } else {
            recTimer?.invalidate(); recTimer = nil
            img?.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    // MARK: Menu

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnapLens")
        img?.isTemplate = true
        statusItem.button?.image = img
        rebuildMenu()
    }

    private func selector(for action: ShortcutAction) -> Selector {
        switch action {
        case .region: return #selector(captureRegion)
        case .full: return #selector(captureFull)
        case .ocr: return #selector(ocrRegion)
        case .describe: return #selector(describeRegion)
        case .lens: return #selector(lensRegion)
        case .record: return #selector(toggleRecording)
        case .history: return #selector(showHistory)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let about = NSMenuItem(title: L("Sobre o SnapLens"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        for action in ShortcutAction.allCases {
            let sc = action.shortcut
            let simple = sc.key.count == 1
            let title = action == .record && Recorder.shared.isRecording ? L("Parar gravação") : action.title
            let item = NSMenuItem(title: title + (action == .history ? "…" : ""),
                                  action: selector(for: action), keyEquivalent: simple ? sc.key.lowercased() : "")
            if simple { item.keyEquivalentModifierMask = sc.menuMask }
            item.target = self
            menu.addItem(item)
            if action == .record { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        let cancelItem = NSMenuItem(title: L("Cancelar captura em andamento"), action: #selector(cancelCapture), keyEquivalent: "")
        cancelItem.target = self
        menu.addItem(cancelItem)
        let diag = NSMenu()
        let d1 = NSMenuItem(title: L("Revelar log no Finder"), action: #selector(revealLog), keyEquivalent: ""); d1.target = self; diag.addItem(d1)
        let d2 = NSMenuItem(title: L("Copiar últimas 200 linhas do log"), action: #selector(copyLog), keyEquivalent: ""); d2.target = self; diag.addItem(d2)
        let diagItem = NSMenuItem(title: L("Diagnóstico"), action: nil, keyEquivalent: ""); diagItem.submenu = diag
        menu.addItem(diagItem)
        let prefs = NSMenuItem(title: L("Ajustes…"), action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Sair do SnapLens"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupHotKeys() {
        applyShortcuts()
        NotificationCenter.default.addObserver(forName: ShortcutAction.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyShortcuts()
                self?.rebuildMenu()
            }
        }
    }

    private func applyShortcuts() {
        for (i, action) in ShortcutAction.allCases.enumerated() {
            let sc = action.shortcut
            let ok = HotKeys.register(id: UInt32(i + 1), keyCode: sc.keyCode, modifiers: sc.modifiers) { [weak self] in
                guard let self else { return }
                switch action {
                case .region: self.captureRegion()
                case .full: self.captureFull()
                case .ocr: self.ocrRegion()
                case .describe: self.describeRegion()
                case .lens: self.lensRegion()
                case .record: self.toggleRecording()
                case .history: self.showHistory()
                }
            }
            if !ok {
                Toast.show(L("Atalho %@ (%@) já está em uso por outro app", sc.display, action.title), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Actions

    @objc func showAbout() {
        let email = "contato@ribeiros.click"
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let credits = NSMutableAttributedString(
            string: L("Captura de tela com anotações, OCR e descrição de imagens com IA, histórico de screenshots e área de transferência.") + "\n\n" + L("Criado por") + "\n",
            attributes: base)
        credits.append(NSAttributedString(string: email, attributes: base.merging([
            .link: URL(string: "mailto:\(email)")!, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)]) { $1 }))
        credits.append(NSAttributedString(string: "\n\n© 2026 · " + L("Todos os direitos reservados"), attributes: base))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SnapLens",
            .applicationVersion: "1.0",
            .version: "",
            .credits: credits,
        ])
    }

    @objc func revealLog() { NSWorkspace.shared.activateFileViewerSelecting([Trace.fileURL]) }
    @objc func copyLog() { copyText(Trace.tail(200)); Toast.show(L("Log copiado — cole no chat"), symbol: "doc.on.doc") }

    @objc func cancelCapture() { overlay?.dismiss(); overlay = nil; OverlayWindow.closeAll() }

    @objc func captureRegion() { Task { await startCapture(region: true, auto: nil) } }
    @objc func captureFull() { Task { await startCapture(region: false, auto: nil) } }
    @objc func describeRegion() { Task { await startCapture(region: true, auto: .describe) } }
    @objc func ocrRegion() { Task { await startCapture(region: true, auto: .ocr) } }
    @objc func lensRegion() { Task { await startCapture(region: true, auto: .lens) } }

    private var isStartingCapture = false

    private func startCapture(region: Bool, auto: ShotAction?) async {
        // Atalho pressionado de novo com o overlay aberto: cancela em vez de empilhar outro.
        Trace.log("startCapture region=\(region) auto=\(String(describing: auto)) overlayActive=\(overlay?.isActive ?? false) anyVisible=\(OverlayWindow.anyVisible) starting=\(isStartingCapture)")
        if (overlay?.isActive ?? false) || OverlayWindow.anyVisible { Trace.log("startCapture: overlay já aberto → cancelando"); cancelCapture(); return }
        guard !isStartingCapture else { return }
        isStartingCapture = true
        defer { isStartingCapture = false }
        Toast.dismiss()
        let screen = Capture.screenUnderMouse()
        let t0 = Date()
        let captured = await Capture.screenImage(for: screen)
        Trace.log("screenImage: \(captured.map { "\($0.width)x\($0.height)" } ?? "nil") em \(Int(Date().timeIntervalSince(t0) * 1000))ms")
        guard let image = captured else {
            CGRequestScreenCaptureAccess()
            Toast.show(L("Permita “Gravação de Tela” ao SnapLens em Ajustes e tente de novo"), symbol: "exclamationmark.triangle.fill")
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if region {
            let o = CaptureOverlay()
            overlay = o
            o.present(screen: screen, image: image, autoAction: auto) { [weak self] action, data in
                self?.overlay = nil
                Task { await self?.finish(action, data: data) }
            }
        } else if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            await finish(.copy, data: data)
        }
    }

    private func finish(_ action: ShotAction, data: Data) async {
        Trace.log("finish action=\(action) bytes=\(data.count)")
        let item = store.addImage(data: data, kind: .screenshot)
        switch action {
        case .copy:
            copyImage(data: data)
            NSSound(named: "Tink")?.play()
            Toast.show(L("Screenshot copiado e salvo no histórico"), symbol: "camera.viewfinder")
        case .save:
            // Dentro do sandbox, .picturesDirectory aponta para o container; usa a pasta Imagens real (entitlement assets.pictures).
            let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) } ?? FileManager.default.homeDirectoryForCurrentUser
            let dir = home.appendingPathComponent("Pictures/SnapLens")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let url = dir.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
            try? data.write(to: url)
            copyImage(data: data)
            NSSound(named: "Tink")?.play()
            Toast.show(L("Salvo em Imagens/SnapLens e copiado"), symbol: "square.and.arrow.down")
        case .ocr:
            await runOCR(on: item)
        case .describe:
            await runDescribe(on: item)
        case .share:
            await share(item)
        case .lens:
            await runLens(on: item)
        }
    }

    // MARK: Google Lens

    /// O Google não tem API pública do Lens; ele aceita `uploadbyurl`, então a imagem vai para o servidor
    /// de links com validade de 1 hora (sem token na Biblioteca) e o Lens abre no navegador.
    func runLens(on item: Item) async {
        guard let url = store.url(for: item), let data = try? Data(contentsOf: url) else { return }
        Toast.show(L("Abrindo no Google Lens…"), symbol: "magnifyingglass")
        do {
            let r = try await ShareClient.upload(data: data, expirySeconds: 3600, once: false)
            guard let lens = ShareClient.lensURL(imageURL: r.image_url ?? r.url) else { return }
            Trace.log("lens: \(r.id)")
            NSWorkspace.shared.open(lens)
            Toast.dismiss()
        } catch {
            Trace.log("lens ERRO: \(error.localizedDescription)")
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Link público

    /// Abre a caixa de validade e, ao confirmar, faz o upload.
    func share(_ item: Item) async {
        guard store.url(for: item) != nil else { return }
        shareOptionsWindow?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "SnapLens — " + L("Compartilhar")
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.contentView = NSHostingView(rootView: ShareOptionsView(onShare: { [weak self] choice, days, destination in
            self?.shareOptionsWindow?.close(); self?.shareOptionsWindow = nil
            let r = choice.resolve(customDays: days)
            Task {
                // Compartilhar de novo um item que já está num Drive: apaga o arquivo antigo para não deixá-lo órfão.
                if item.shareDrive != nil { await self?.revoke(item, quiet: true) }
                if let drive = destination.drive { await self?.uploadToDrive(item, drive: drive, expirySeconds: r.seconds) }
                else { await self?.upload(item, expirySeconds: r.seconds, once: r.once) }
            }
        }, onCancel: { [weak self] in
            self?.shareOptionsWindow?.close(); self?.shareOptionsWindow = nil
        }))
        w.center()
        shareOptionsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func upload(_ item: Item, expirySeconds: Int, once: Bool) async {
        guard let url = store.url(for: item), let data = try? Data(contentsOf: url) else { return }
        Toast.show(L("Enviando para %@…", ShareConfig.server.replacingOccurrences(of: "https://", with: "")), symbol: "link")
        do {
            let r = try await ShareClient.upload(data: data, expirySeconds: expirySeconds, once: once)
            var it = item
            it.shareID = r.id
            it.shareURL = r.url
            it.shareExpires = r.expires_at.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            it.shareToken = r.delete_token
            it.shareOnce = r.once
            it.shareDrive = nil
            store.update(it)
            copyText(r.url)
            NSSound(named: "Pop")?.play()
            let once = r.once ?? false
            Toast.show(L("Link copiado · %@", expiryText(it.shareExpires)) + (once ? " · " + L("visualização única") : ""), symbol: "link")
            showShareResult(url: r.url, expires: it.shareExpires, token: r.delete_token, once: once)
        } catch {
            Trace.log("share ERRO: \(error.localizedDescription)")
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Envia para a pasta SnapLens do OneDrive / Google Drive e cria um link de leitura público.
    private func uploadToDrive(_ item: Item, drive: CloudDrive, expirySeconds: Int) async {
        guard let url = store.url(for: item), let data = try? Data(contentsOf: url) else { return }
        Toast.show(L("Enviando para %@…", drive.name), symbol: "icloud.and.arrow.up")
        let expires = expirySeconds > 0 ? Date().addingTimeInterval(TimeInterval(expirySeconds)) : nil
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = fmt.string(from: item.date)
        do {
            let r = try await CloudClient.upload(drive, data: data, filename: "SnapLens \(stamp).png", expires: expires)
            var it = item
            it.shareID = r.id
            it.shareURL = r.url
            it.shareExpires = expires
            it.shareToken = nil
            it.shareOnce = nil
            it.shareDrive = drive.rawValue
            store.update(it)
            copyText(r.url)
            NSSound(named: "Pop")?.play()
            Toast.show(L("Link copiado · %@", expiryText(expires)), symbol: "icloud")
            showShareResult(url: r.url, expires: expires, token: "", once: false, drive: drive)
        } catch {
            Trace.log("share \(drive.rawValue) ERRO: \(error.localizedDescription)")
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Links em Drives não expiram sozinhos (o Google não permite; o OneDrive pessoal também não):
    /// o próprio app apaga os arquivos vencidos ao abrir e a cada hora.
    private var driveExpiryTimer: Timer?
    func startDriveExpiry() {
        Task { await purgeExpiredDriveShares() }
        driveExpiryTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.purgeExpiredDriveShares() }
        }
    }

    private func purgeExpiredDriveShares() async {
        for item in store.items where item.shareDrive != nil && (item.shareExpires.map { $0 < Date() } ?? false) {
            await revoke(item, quiet: true)
        }
    }

    func revoke(_ item: Item, quiet: Bool = false) async {
        guard let id = item.shareID else { return }
        do {
            if let drive = item.shareDrive.flatMap(CloudDrive.init(rawValue:)) {
                try await CloudClient.delete(drive, id: id)
            } else {
                guard let token = item.shareToken else { return }
                try await ShareClient.revoke(id: id, token: token)
            }
            guard var it = store.items.first(where: { $0.id == item.id }) else { return }
            it.shareID = nil; it.shareURL = nil; it.shareExpires = nil; it.shareToken = nil; it.shareOnce = nil; it.shareDrive = nil
            store.update(it)
            if quiet { Trace.log("share: link vencido apagado (\(item.shareDrive ?? "servidor"))"); return }
            Toast.show(L("Link revogado"), symbol: "link.badge.plus")
        } catch {
            Trace.log("revogar ERRO: \(error.localizedDescription)")
            if !quiet { Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill") }
        }
    }

    func runOCR(on item: Item) async {
        guard let url = store.url(for: item) else { return }
        Toast.show(L("Reconhecendo texto…"), symbol: "text.viewfinder")
        let text = await OCR.recognize(url: url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            Toast.show(L("Nenhum texto encontrado"), symbol: "exclamationmark.triangle.fill")
            return
        }
        copyText(text)
        store.addText(text, kind: .ocr)
        NSSound(named: "Pop")?.play()
        Toast.dismiss()
        OCRResultWindow.show(text: text) { [weak self] t in
            self?.copyText(t)
            Toast.show(L("Texto copiado"))
        }
    }

    func runDescribe(on item: Item) async {
        guard let url = store.url(for: item) else { return }
        let provider = Provider.active
        Toast.show(L("Analisando com %@…", provider?.shortName ?? "Apple Vision"), symbol: "sparkles")
        do {
            let text: String
            if let provider { text = try await AIClient.describe(imageURL: url, provider: provider) }
            else { text = await OCR.nativeDescription(url: url) }
            copyText(text)
            store.addText(text, kind: .ai, source: provider?.shortName ?? L("Nativo"))
            NSSound(named: "Pop")?.play()
            Toast.show(L("Descrição copiada: %@", String(text.prefix(80))), symbol: "sparkles")
        } catch {
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "SnapLens — " + L("Ajustes")
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showShareResult(url: String, expires: Date?, token: String, once: Bool, drive: CloudDrive? = nil) {
        if shareWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "SnapLens — " + L("Link compartilhado")
            w.isReleasedWhenClosed = false
            w.center()
            shareWindow = w
        }
        shareWindow?.contentView = NSHostingView(rootView: ShareResultView(url: url, expires: expires, token: token, once: once, drive: drive) { [weak self] in
            self?.shareWindow?.close()
        })
        NSApp.activate(ignoringOtherApps: true)
        shareWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showHistory() {
        if historyWindow == nil {
            let view = HistoryView(store: store, onDescribe: { [weak self] item in
                Task { await self?.runDescribe(on: item) }
            }, onOCR: { [weak self] item in
                Task { await self?.runOCR(on: item) }
            }, onCopyImage: { [weak self] item in
                guard let self, let u = self.store.url(for: item), let d = try? Data(contentsOf: u) else { return }
                self.copyImage(data: d)
                Toast.show(L("Imagem copiada"))
            }, onCopyText: { [weak self] text in
                self?.copyText(text)
                Toast.show(L("Texto copiado"))
            }, onPlay: { [weak self] item in
                if let u = self?.store.url(for: item) { NSWorkspace.shared.open(u) }
            }, onShare: { [weak self] item in
                Task { await self?.share(item) }
            }, onRevoke: { [weak self] item in
                Task { await self?.revoke(item) }
            }, onCopyImageData: { [weak self] data in
                self?.copyImage(data: data)
            }, onLens: { [weak self] item in
                Task { await self?.runLens(on: item) }
            })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "SnapLens — " + L("Biblioteca")
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            historyWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Pasteboard

    private func copyImage(data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let img = NSImage(data: data) { pb.writeObjects([img]) }
        lastChangeCount = pb.changeCount // não registrar nossa própria cópia
    }

    private func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    private func startClipboardMonitor() {
        clipTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollClipboard() }
        }
    }

    private var clipboardReading = false

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount, !clipboardReading else { return }
        lastChangeCount = pb.changeCount
        // Ignora conteúdo marcado como oculto/transitório (ex.: gerenciadores de senha).
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }

        // A leitura do conteúdo pode bloquear: dados "prometidos" por outro app só chegam quando esse app
        // responde, e após o sleep ele pode estar congelado. Por isso roda fora da thread principal.
        clipboardReading = true
        let lastText = store.items.first(where: { $0.kind == .clipboardText || $0.kind == .ocr })?.text
        Task.detached(priority: .utility) { [weak self] in
            let pb = NSPasteboard.general
            var text: String?
            var image: Data?
            if let t = pb.string(forType: .string), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = t
            } else if let d = pb.data(forType: .png) {
                image = d
            } else if let tiff = pb.data(forType: .tiff), tiff.count < 64 * 1024 * 1024,
                      let img = NSImage(data: tiff), let d = pngData(from: img) {
                image = d
            }
            await MainActor.run {
                guard let self else { return }
                self.clipboardReading = false
                if let text, text != lastText { self.store.addText(text, kind: .clipboardText) }
                else if let image { self.store.addImage(data: image, kind: .clipboardImage) }
            }
        }
    }
}
