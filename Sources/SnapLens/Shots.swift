import AppKit
import SwiftUI

/// `SnapLens --render-shots <pasta>`: gera os prints do site a partir da UI real,
/// sobre um "desktop" sintético (nenhuma captura de tela do usuário é usada).
@MainActor
enum Shots {
    static func render(to dir: URL, language: String? = nil) {
        let previousLang = L10n.selection
        if let language { L10n.selection = language }
        defer { if language != nil { L10n.selection = previousLang } }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let desktop = makeDesktop(size: CGSize(width: 1440, height: 900))
        write(desktop, dir.appendingPathComponent("desktop.png"))

        // 1. Overlay de captura com seleção, anotações e barra de ferramentas.
        if let cg = desktop.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let v = CaptureOverlay.preview(background: cg, size: desktop.size, selection: CGRect(x: 300, y: 190, width: 840, height: 470), annotated: true)
            if let img = snapshot(v, size: desktop.size) { write(img, dir.appendingPathComponent("overlay.png")) }
        }

        // 2. Biblioteca com itens de exemplo (store temporário).
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("snaplens-shots-\(UUID().uuidString)")
        let store = Store(dir: tmp)
        for (i, crop) in sampleCrops(from: desktop).enumerated() {
            if let data = pngData(from: crop) {
                var it = store.addImage(data: data, kind: i == 3 ? .clipboardImage : .screenshot)
                if i == 0 {
                    it.shareID = "k3Qz8vLm2a"; it.shareURL = "https://lens.ribeiros.click/s/k3Qz8vLm2a"
                    it.shareExpires = Date().addingTimeInterval(6 * 86400); it.shareToken = "x"
                    store.update(it)
                }
            }
        }
        store.addText(L("Relatório de vendas — 3º trimestre") + "\n" + L("Região Sul: R$ 182.400 (+12%)\nRegião Sudeste: R$ 401.950 (+8%)"), kind: .ocr)
        store.addText(L("A imagem mostra uma tabela de vendas por região com três colunas (Região, Receita, Variação)…"), kind: .ai, source: "Claude")
        store.addText("https://developer.apple.com/documentation/vision", kind: .clipboardText)
        let history = HistoryView(store: store, onDescribe: { _ in }, onOCR: { _ in }, onCopyImage: { _ in }, onCopyText: { _ in },
                                  onPlay: { _ in }, onShare: { _ in }, onRevoke: { _ in })
        if let img = snapshot(NSHostingView(rootView: history), size: CGSize(width: 860, height: 560)) {
            write(img, dir.appendingPathComponent("biblioteca.png"))
        }

        // 3. Ajustes — com valores neutros (não expõe as preferências reais do usuário).
        let ud = UserDefaults.standard
        let savedProvider = ud.string(forKey: "activeProvider")
        ud.set("", forKey: "activeProvider")
        if let img = snapshot(NSHostingView(rootView: SettingsView()), size: CGSize(width: 520, height: 900)) {
            write(img, dir.appendingPathComponent("ajustes.png"))
        }
        if let savedProvider { ud.set(savedProvider, forKey: "activeProvider") } else { ud.removeObject(forKey: "activeProvider") }
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: Quadros do vídeo de demonstração

    static func renderVideoFrames(to dir: URL, language: String?) {
        let previousLang = L10n.selection
        if let language { L10n.selection = language }
        defer { if language != nil { L10n.selection = previousLang } }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 1440, height: 900)
        let desktop = makeDesktop(size: size)
        let sel = CGRect(x: 300, y: 190, width: 840, height: 470)
        let icon = Bundle.main.path(forResource: "AppIcon", ofType: "icns").flatMap { NSImage(contentsOfFile: $0) }

        write(card(size: size, icon: icon, title: "SnapLens", subtitle: L("Capture, anote e compartilhe sem sair do teclado."), footer: "macOS"), dir.appendingPathComponent("01_title.png"))
        write(desktop, dir.appendingPathComponent("02_desktop.png"))
        if let cg = desktop.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            for (name, selection, annotated) in [("03_overlay_empty", nil, false), ("04_overlay_selection", sel, false), ("05_overlay_annotated", sel, true)] as [(String, CGRect?, Bool)] {
                if let img = snapshot(CaptureOverlay.preview(background: cg, size: size, selection: selection, annotated: annotated), size: size) {
                    write(img, dir.appendingPathComponent(name + ".png"))
                }
            }
        }
        let ocrText = L("Relatório de vendas — 3º trimestre") + "\n" + L("Região Sul: R$ 182.400 (+12%)\nRegião Sudeste: R$ 401.950 (+8%)")
        if let w = snapshot(NSHostingView(rootView: OCRResultView(original: ocrText, onCopy: { _ in })), size: CGSize(width: 560, height: 300)) {
            write(window(w, title: "SnapLens — " + L("Resultado do OCR"), over: desktop), dir.appendingPathComponent("06_ocr.png"))
        }
        if let w = snapshot(NSHostingView(rootView: ShareResultView(url: "https://lens.ribeiros.click/s/k3Qz8vLm2a", expires: Date().addingTimeInterval(7 * 86400), token: "4f9c2e7a1b8d3c6e5a0f9b2d7c4e1a8f", once: false, onClose: {})), size: CGSize(width: 460, height: 300)) {
            write(window(w, title: "SnapLens — " + L("Link compartilhado"), over: desktop), dir.appendingPathComponent("07_share.png"))
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("snaplens-video-\(UUID().uuidString)")
        let store = Store(dir: tmp)
        for (i, crop) in sampleCrops(from: desktop).enumerated() {
            if let data = pngData(from: crop) {
                var it = store.addImage(data: data, kind: i == 3 ? .clipboardImage : .screenshot)
                if i == 0 { it.shareID = "k3Qz8vLm2a"; it.shareURL = "https://lens.ribeiros.click/s/k3Qz8vLm2a"; it.shareExpires = Date().addingTimeInterval(6 * 86400); it.shareToken = "x"; store.update(it) }
            }
        }
        store.addText(ocrText, kind: .ocr)
        store.addText(L("A imagem mostra uma tabela de vendas por região com três colunas (Região, Receita, Variação)…"), kind: .ai, source: "Claude")
        let history = HistoryView(store: store, onDescribe: { _ in }, onOCR: { _ in }, onCopyImage: { _ in }, onCopyText: { _ in }, onPlay: { _ in }, onShare: { _ in }, onRevoke: { _ in })
        if let w = snapshot(NSHostingView(rootView: history), size: CGSize(width: 900, height: 560)) {
            write(window(w, title: "SnapLens — " + L("Biblioteca"), over: desktop), dir.appendingPathComponent("08_library.png"))
        }
        let ud = UserDefaults.standard; let savedProvider = ud.string(forKey: "activeProvider"); ud.set("", forKey: "activeProvider")
        if let w = snapshot(NSHostingView(rootView: SettingsView()), size: CGSize(width: 520, height: 700)) {
            write(window(w, title: "SnapLens — " + L("Ajustes"), over: desktop), dir.appendingPathComponent("09_settings.png"))
        }
        if let savedProvider { ud.set(savedProvider, forKey: "activeProvider") } else { ud.removeObject(forKey: "activeProvider") }
        write(card(size: size, icon: icon, title: "lens.ribeiros.click", subtitle: L("Grátis e de código aberto. Baixe para macOS 15 ou mais recente."), footer: "github.com/ribeiros-click/snaplens"), dir.appendingPathComponent("10_end.png"))
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Cartão de abertura/encerramento na identidade do site (musgo + areia).
    private static func card(size: CGSize, icon: NSImage?, title: String, subtitle: String, footer: String) -> NSImage {
        NSImage(size: size, flipped: false) { r in
            NSColor(red: 0.953, green: 0.933, blue: 0.894, alpha: 1).setFill(); r.fill()
            NSGradient(colors: [NSColor(red: 0.373, green: 0.478, blue: 0.208, alpha: 0.18), NSColor(red: 0.541, green: 0.416, blue: 0.235, alpha: 0.0)])!
                .draw(in: NSBezierPath(ovalIn: NSRect(x: r.midX - 520, y: r.midY - 140, width: 1040, height: 700)), relativeCenterPosition: .zero)
            let iconSize: CGFloat = 200
            if let icon {
                NSGraphicsContext.saveGraphicsState()
                let sh = NSShadow(); sh.shadowColor = NSColor(red: 0.27, green: 0.2, blue: 0.09, alpha: 0.35); sh.shadowBlurRadius = 40; sh.shadowOffset = NSSize(width: 0, height: -14); sh.set()
                icon.draw(in: NSRect(x: r.midX - iconSize / 2, y: r.midY + 40, width: iconSize, height: iconSize))
                NSGraphicsContext.restoreGraphicsState()
            }
            let para = NSMutableParagraphStyle(); para.alignment = .center
            let t = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 84, weight: .bold), .foregroundColor: NSColor(red: 0.165, green: 0.141, blue: 0.098, alpha: 1), .paragraphStyle: para, .kern: -2])
            t.draw(in: NSRect(x: 0, y: r.midY - 80, width: r.width, height: 110))
            let st = NSAttributedString(string: subtitle, attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: NSColor(red: 0.42, green: 0.376, blue: 0.32, alpha: 1), .paragraphStyle: para])
            st.draw(in: NSRect(x: 120, y: r.midY - 180, width: r.width - 240, height: 90))
            let f = NSAttributedString(string: footer, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 24, weight: .medium), .foregroundColor: NSColor(red: 0.373, green: 0.478, blue: 0.208, alpha: 1), .paragraphStyle: para])
            f.draw(in: NSRect(x: 0, y: 90, width: r.width, height: 40))
            return true
        }
    }

    /// Janela com barra de título e sombra sobre o desktop escurecido.
    private static func window(_ content: NSImage, title: String, over desktop: NSImage) -> NSImage {
        NSImage(size: desktop.size, flipped: false) { r in
            desktop.draw(in: r)
            NSColor.black.withAlphaComponent(0.38).setFill(); r.fill()
            let tb: CGFloat = 36
            let w = content.size.width, h = content.size.height + tb
            let frame = NSRect(x: (r.width - w) / 2, y: (r.height - h) / 2, width: w, height: h)
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.5); sh.shadowBlurRadius = 50; sh.shadowOffset = NSSize(width: 0, height: -20); sh.set()
            NSColor(white: 0.93, alpha: 1).setFill(); NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).addClip()
            content.draw(in: NSRect(x: frame.minX, y: frame.minY, width: w, height: content.size.height))
            NSColor(white: 0.90, alpha: 1).setFill(); NSRect(x: frame.minX, y: frame.maxY - tb, width: w, height: tb).fill()
            for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                c.setFill(); NSBezierPath(ovalIn: NSRect(x: frame.minX + 14 + CGFloat(i) * 20, y: frame.maxY - tb + 11, width: 13, height: 13)).fill()
            }
            let para = NSMutableParagraphStyle(); para.alignment = .center
            NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.darkGray, .paragraphStyle: para])
                .draw(in: NSRect(x: frame.minX, y: frame.maxY - tb + 9, width: w, height: 18))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }

    // MARK: Snapshot offscreen

    private static func snapshot(_ view: NSView, size: CGSize) -> NSImage? {
        let w = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(origin: .zero, size: size)
        w.contentView = view
        w.orderFront(nil) // fora de todas as telas: não aparece
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        w.orderOut(nil)
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    private static func write(_ img: NSImage, _ url: URL) {
        if let d = pngData(from: img) { try? d.write(to: url) }
    }

    // MARK: Desktop sintético

    private static func makeDesktop(size: CGSize) -> NSImage {
        NSImage(size: size, flipped: true) { r in
            NSGradient(colors: [NSColor(red: 0.27, green: 0.33, blue: 0.19, alpha: 1),
                                NSColor(red: 0.50, green: 0.42, blue: 0.28, alpha: 1),
                                NSColor(red: 0.84, green: 0.76, blue: 0.58, alpha: 1)])!.draw(in: r, angle: -35)
            // barra de menus
            NSColor(white: 1, alpha: 0.75).setFill(); NSRect(x: 0, y: 0, width: r.width, height: 26).fill()
            text("  Finder   " + L("Arquivo   Editar   Visualizar   Ir   Janela   Ajuda"), at: CGPoint(x: 8, y: 5), size: 13, weight: .semibold, color: .black)
            // janela
            let win = NSRect(x: 220, y: 110, width: 1000, height: 640)
            NSColor.black.withAlphaComponent(0.25).setFill(); NSBezierPath(roundedRect: win.offsetBy(dx: 0, dy: 8).insetBy(dx: -4, dy: -4), xRadius: 14, yRadius: 14).fill()
            NSColor.white.setFill(); NSBezierPath(roundedRect: win, xRadius: 12, yRadius: 12).fill()
            NSColor(white: 0.93, alpha: 1).setFill()
            let title = NSBezierPath(roundedRect: NSRect(x: win.minX, y: win.minY, width: win.width, height: 48), xRadius: 12, yRadius: 12)
            title.appendRect(NSRect(x: win.minX, y: win.minY + 24, width: win.width, height: 24)); title.fill()
            for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                c.setFill(); NSBezierPath(ovalIn: NSRect(x: win.minX + 14 + CGFloat(i) * 20, y: win.minY + 17, width: 13, height: 13)).fill()
            }
            text(L("Relatório de vendas — 3º trimestre") + ".pages", at: CGPoint(x: win.midX - 140, y: win.minY + 15), size: 13, weight: .medium, color: .darkGray)
            text(L("Relatório de vendas — 3º trimestre"), at: CGPoint(x: win.minX + 60, y: win.minY + 90), size: 28, weight: .bold, color: .black)
            text(L("Resumo por região"), at: CGPoint(x: win.minX + 60, y: win.minY + 150), size: 17, weight: .semibold, color: .darkGray)
            let rows: [[String]] = [[L("Região"), L("Receita"), L("Variação")], [L("Sul"), "R$ 182.400", "+12%"], [L("Sudeste"), "R$ 401.950", "+8%"],
                                    [L("Nordeste"), "R$ 96.300", "+21%"], [L("Norte"), "R$ 41.700", "−3%"], [L("Centro-Oeste"), "R$ 77.250", "+5%"]]
            for (ri, row) in rows.enumerated() {
                let y = win.minY + 190 + CGFloat(ri) * 36
                if ri == 0 { NSColor(white: 0.95, alpha: 1).setFill(); NSRect(x: win.minX + 60, y: y - 8, width: 620, height: 34).fill() }
                else { NSColor(white: 0.88, alpha: 1).setFill(); NSRect(x: win.minX + 60, y: y + 26, width: 620, height: 1).fill() }
                for (ci, cell) in row.enumerated() {
                    text(cell, at: CGPoint(x: win.minX + 72 + CGFloat(ci) * 210, y: y), size: 15,
                         weight: ri == 0 ? .semibold : .regular, color: cell.hasPrefix("−") ? .systemRed : .black)
                }
            }
            for (i, w) in [CGFloat(560), 610, 480, 590, 300].enumerated() {
                NSColor(white: 0.85, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: win.minX + 60, y: win.minY + 430 + CGFloat(i) * 26, width: w, height: 12), xRadius: 6, yRadius: 6).fill()
            }
            // dock
            let dock = NSRect(x: r.midX - 260, y: r.height - 74, width: 520, height: 62)
            NSColor(white: 1, alpha: 0.35).setFill(); NSBezierPath(roundedRect: dock, xRadius: 18, yRadius: 18).fill()
            for i in 0..<9 {
                NSColor(hue: 0.08 + CGFloat(i) * 0.035, saturation: 0.35, brightness: 0.78, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: dock.minX + 14 + CGFloat(i) * 56, y: dock.minY + 10, width: 42, height: 42), xRadius: 10, yRadius: 10).fill()
            }
            return true
        }
    }

    private static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: p)
    }

    private static func sampleCrops(from desktop: NSImage) -> [NSImage] {
        let rects = [CGRect(x: 300, y: 190, width: 840, height: 470), CGRect(x: 220, y: 110, width: 1000, height: 640),
                     CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 260, y: 300, width: 500, height: 260)]
        return rects.map { r in
            NSImage(size: r.size, flipped: false) { _ in
                desktop.draw(in: CGRect(origin: .zero, size: r.size), from: CGRect(x: r.minX, y: desktop.size.height - r.maxY, width: r.width, height: r.height),
                             operation: .copy, fraction: 1)
                return true
            }
        }
    }
}
