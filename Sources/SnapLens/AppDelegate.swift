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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        setupMenu()
        setupHotKeys()
        startClipboardMonitor()
        NotificationCenter.default.addObserver(forName: Recorder.stateChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordingStateChanged() }
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
                    Toast.show("Gravando… use o atalho ou o menu para parar", symbol: "record.circle")
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
        case .record: return #selector(toggleRecording)
        case .history: return #selector(showHistory)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        for action in ShortcutAction.allCases {
            let sc = action.shortcut
            let simple = sc.key.count == 1
            let title = action == .record && Recorder.shared.isRecording ? "Parar gravação" : action.title
            let item = NSMenuItem(title: title + (action == .history ? "…" : ""),
                                  action: selector(for: action), keyEquivalent: simple ? sc.key.lowercased() : "")
            if simple { item.keyEquivalentModifierMask = sc.menuMask }
            item.target = self
            menu.addItem(item)
            if action == .record { menu.addItem(.separator()) }
        }
        let prefs = NSMenuItem(title: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do SnapLens", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
                case .record: self.toggleRecording()
                case .history: self.showHistory()
                }
            }
            if !ok {
                Toast.show("Atalho \(sc.display) (\(action.title)) já está em uso por outro app", symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    // MARK: Actions

    @objc func captureRegion() { Task { await startCapture(region: true, auto: nil) } }
    @objc func captureFull() { Task { await startCapture(region: false, auto: nil) } }
    @objc func describeRegion() { Task { await startCapture(region: true, auto: .describe) } }
    @objc func ocrRegion() { Task { await startCapture(region: true, auto: .ocr) } }

    private func startCapture(region: Bool, auto: ShotAction?) async {
        Toast.dismiss()
        let screen = Capture.screenUnderMouse()
        guard let image = await Capture.screenImage(for: screen) else {
            CGRequestScreenCaptureAccess()
            Toast.show("Permita “Gravação de Tela” ao SnapLens em Ajustes e tente de novo", symbol: "exclamationmark.triangle.fill")
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
        let item = store.addImage(data: data, kind: .screenshot)
        switch action {
        case .copy:
            copyImage(data: data)
            NSSound(named: "Tink")?.play()
            Toast.show("Screenshot copiado e salvo no histórico", symbol: "camera.viewfinder")
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
            Toast.show("Salvo em Imagens/SnapLens e copiado", symbol: "square.and.arrow.down")
        case .ocr:
            await runOCR(on: item)
        case .describe:
            await runDescribe(on: item)
        }
    }

    func runOCR(on item: Item) async {
        guard let url = store.url(for: item) else { return }
        Toast.show("Reconhecendo texto…", symbol: "text.viewfinder")
        let text = await OCR.recognize(url: url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            Toast.show("Nenhum texto encontrado", symbol: "exclamationmark.triangle.fill")
            return
        }
        copyText(text)
        store.addText(text, kind: .ocr)
        NSSound(named: "Pop")?.play()
        Toast.dismiss()
        OCRResultWindow.show(text: text) { [weak self] t in
            self?.copyText(t)
            Toast.show("Texto copiado")
        }
    }

    func runDescribe(on item: Item) async {
        guard let url = store.url(for: item) else { return }
        let provider = Provider.active
        Toast.show("Analisando com \(provider?.shortName ?? "Apple Vision")…", symbol: "sparkles")
        do {
            let text: String
            if let provider { text = try await AIClient.describe(imageURL: url, provider: provider) }
            else { text = await OCR.nativeDescription(url: url) }
            copyText(text)
            store.addText(text, kind: .ai, source: provider?.shortName ?? "Nativo")
            NSSound(named: "Pop")?.play()
            Toast.show("Descrição copiada: \(text.prefix(80))", symbol: "sparkles")
        } catch {
            Toast.show(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 840),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "SnapLens — Ajustes"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
                Toast.show("Imagem copiada")
            }, onCopyText: { [weak self] text in
                self?.copyText(text)
                Toast.show("Texto copiado")
            }, onPlay: { [weak self] item in
                if let u = self?.store.url(for: item) { NSWorkspace.shared.open(u) }
            })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "SnapLens — Biblioteca"
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

    private func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        // Ignora conteúdo marcado como oculto/transitório (ex.: gerenciadores de senha).
        let types = pb.types?.map(\.rawValue) ?? []
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") { return }

        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if store.items.first(where: { $0.kind == .clipboardText || $0.kind == .ocr })?.text != text {
                store.addText(text, kind: .clipboardText)
            }
        } else if let data = pb.data(forType: .png)
                    ?? pb.data(forType: .tiff).flatMap({ NSImage(data: $0) }).flatMap(pngData(from:)) {
            store.addImage(data: data, kind: .clipboardImage)
        }
    }
}
