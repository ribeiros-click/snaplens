import AppKit
import UniformTypeIdentifiers

/// Exportação de itens da biblioteca (imagem, vídeo, texto) para arquivos.
@MainActor
enum Exporter {
    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: d)
    }

    static func export(_ item: Item, store: Store) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        switch item.kind {
        case .video:
            panel.allowedContentTypes = [.mpeg4Movie]
            panel.nameFieldStringValue = L("Gravação") + " \(stamp(item.date)).mp4"
        case .screenshot, .clipboardImage:
            panel.allowedContentTypes = [.png, .jpeg, .tiff]
            panel.nameFieldStringValue = "Screenshot \(stamp(item.date)).png"
        default:
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = L("Texto") + " \(stamp(item.date)).txt"
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try write(item, to: dest, store: store)
            Toast.show(L("Exportado: %@", dest.lastPathComponent), symbol: "square.and.arrow.up")
        } catch {
            Toast.show(L("Falha ao exportar: %@", error.localizedDescription), symbol: "exclamationmark.triangle.fill")
        }
    }

    private static func write(_ item: Item, to dest: URL, store: Store) throws {
        try? FileManager.default.removeItem(at: dest)
        if item.kind.isText {
            try (item.text ?? "").write(to: dest, atomically: true, encoding: .utf8)
        } else if let src = store.url(for: item) {
            if item.kind.isImage, let type = UTType(filenameExtension: dest.pathExtension), type != .png,
               let img = NSImage(contentsOf: src), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                let fileType: NSBitmapImageRep.FileType = type.conforms(to: .jpeg) ? .jpeg : .tiff
                try rep.representation(using: fileType, properties: [.compressionFactor: 0.92])?.write(to: dest)
            } else {
                try FileManager.default.copyItem(at: src, to: dest)
            }
        }
    }

    /// Exporta toda a biblioteca para uma pasta: Screenshots/, Vídeos/ e Textos.txt.
    static func exportAll(store: Store) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Exportar aqui")
        panel.message = L("Escolha onde salvar a exportação da biblioteca")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let fm = FileManager.default
        let root = parent.appendingPathComponent("SnapLens Export \(stamp(Date()))", isDirectory: true)
        let shots = root.appendingPathComponent("Screenshots", isDirectory: true)
        let vids = root.appendingPathComponent(L("Vídeos"), isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            var count = 0
            var texts = ""
            for item in store.items.reversed() {
                if item.kind == .video {
                    try fm.createDirectory(at: vids, withIntermediateDirectories: true)
                    try write(item, to: vids.appendingPathComponent(L("Gravação") + " \(stamp(item.date)).mp4"), store: store)
                    count += 1
                } else if item.kind.isImage {
                    try fm.createDirectory(at: shots, withIntermediateDirectories: true)
                    try write(item, to: shots.appendingPathComponent("\(item.kind == .screenshot ? "Screenshot" : "Clipboard") \(stamp(item.date)).png"), store: store)
                    count += 1
                } else if let t = item.text {
                    let label = item.kind == .ocr ? "OCR" : item.kind == .ai ? L("IA") : "Clipboard"
                    texts += "[\(stamp(item.date)) · \(label)]\n\(t)\n\n----------------------------------------\n\n"
                    count += 1
                }
            }
            if !texts.isEmpty { try texts.write(to: root.appendingPathComponent(L("Textos") + ".txt"), atomically: true, encoding: .utf8) }
            Toast.show(L("%@ itens exportados", String(count)), symbol: "square.and.arrow.up")
            NSWorkspace.shared.activateFileViewerSelecting([root])
        } catch {
            Toast.show(L("Falha ao exportar: %@", error.localizedDescription), symbol: "exclamationmark.triangle.fill")
        }
    }
}
