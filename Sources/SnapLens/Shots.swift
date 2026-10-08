import AppKit
import SwiftUI

/// `SnapLens --render-shots <pasta>`: gera os prints do site a partir da UI real,
/// sobre um "desktop" sintético (nenhuma captura de tela do usuário é usada).
@MainActor
enum Shots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let desktop = makeDesktop(size: CGSize(width: 1440, height: 900))
        write(desktop, dir.appendingPathComponent("desktop.png"))

        // 1. Overlay de captura com seleção, anotações e barra de ferramentas.
        if let cg = desktop.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let v = CaptureOverlay.preview(background: cg, size: desktop.size, selection: CGRect(x: 300, y: 190, width: 840, height: 470))
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
        store.addText("Relatório de vendas — 3º trimestre\nRegião Sul: R$ 182.400 (+12%)\nRegião Sudeste: R$ 401.950 (+8%)", kind: .ocr)
        store.addText("A imagem mostra uma tabela de vendas por região com três colunas (Região, Receita, Variação)…", kind: .ai, source: "Claude")
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
            text("  Finder   Arquivo   Editar   Visualizar   Ir   Janela   Ajuda", at: CGPoint(x: 8, y: 5), size: 13, weight: .semibold, color: .black)
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
            text("Relatório de vendas — 3º trimestre.pages", at: CGPoint(x: win.midX - 140, y: win.minY + 15), size: 13, weight: .medium, color: .darkGray)
            text("Relatório de vendas — 3º trimestre", at: CGPoint(x: win.minX + 60, y: win.minY + 90), size: 28, weight: .bold, color: .black)
            text("Resumo por região", at: CGPoint(x: win.minX + 60, y: win.minY + 150), size: 17, weight: .semibold, color: .darkGray)
            let rows: [[String]] = [["Região", "Receita", "Variação"], ["Sul", "R$ 182.400", "+12%"], ["Sudeste", "R$ 401.950", "+8%"],
                                    ["Nordeste", "R$ 96.300", "+21%"], ["Norte", "R$ 41.700", "−3%"], ["Centro-Oeste", "R$ 77.250", "+5%"]]
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
