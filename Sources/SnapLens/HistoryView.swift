import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var store: Store
    var onDescribe: (Item) -> Void
    var onOCR: (Item) -> Void
    var onCopyImage: (Item) -> Void
    var onCopyText: (String) -> Void
    var onPlay: (Item) -> Void
    var onShare: (Item) -> Void
    var onRevoke: (Item) -> Void
    var onCopyImageData: (Data) -> Void

    enum Tab: String, CaseIterable { case images = "Imagens", videos = "Vídeos", texts = "Texto" }
    @State private var tab: Tab = .images
    @State private var query = ""
    @State private var selected: [UUID] = []   // ordem de seleção = ordem na montagem

    private var images: [Item] { store.items.filter { $0.kind.isImage } }
    private var videos: [Item] { store.items.filter { $0.kind == .video } }
    private var texts: [Item] {
        store.items.filter { $0.kind.isText && (query.isEmpty || ($0.text ?? "").localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text(L($0.rawValue)) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                if tab == .texts {
                    TextField(L("Buscar…"), text: $query).textFieldStyle(.roundedBorder)
                }
                if tab == .images, !selected.isEmpty {
                    Text(L("%@ selecionada(s)", String(selected.count))).font(.callout).foregroundStyle(.secondary)
                    Button { combine(copy: true) } label: { Label(L("Copiar juntas"), systemImage: "doc.on.doc") }
                    Button { combine(copy: false) } label: { Label(L("Baixar juntas"), systemImage: "square.and.arrow.down") }
                    Button { selected.removeAll() } label: { Label(L("Limpar seleção"), systemImage: "xmark.circle") }
                }
                Spacer()
                Button { Exporter.exportAll(store: store) } label: {
                    Label(L("Exportar tudo…"), systemImage: "square.and.arrow.up.on.square")
                }
                Button(role: .destructive) {
                    switch tab {
                    case .images: store.clear { $0.isImage }
                    case .videos: store.clear { $0 == .video }
                    case .texts: store.clear { $0.isText }
                    }
                } label: {
                    Label(L("Limpar"), systemImage: "trash")
                }
            }
            .padding(12)
            Divider()
            switch tab {
            case .images: imageGrid
            case .videos: videoGrid
            case .texts: textList
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var imageGrid: some View {
        Group {
            if images.isEmpty { empty(L("Nenhum screenshot ainda.\nUse %@ para capturar uma seleção.", ShortcutAction.region.shortcut.display)) }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(images) { item in
                            ImageCard(item: item, store: store, onDescribe: onDescribe, onOCR: onOCR, onCopy: onCopyImage,
                                      onShare: onShare, onRevoke: onRevoke, onCopyText: onCopyText,
                                      selectionIndex: selected.firstIndex(of: item.id),
                                      onToggleSelect: { toggle(item) })
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var videoGrid: some View {
        Group {
            if videos.isEmpty { empty(L("Nenhuma gravação ainda.\nUse %@ para gravar a tela.", ShortcutAction.record.shortcut.display)) }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(videos) { item in VideoCard(item: item, store: store, onPlay: onPlay) }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var textList: some View {
        Group {
            if texts.isEmpty { empty(L("Nenhum texto no histórico.")) }
            else {
                List(texts) { item in
                    TextRow(item: item, store: store, onCopy: onCopyText)
                }
            }
        }
    }

    private func toggle(_ item: Item) {
        if let i = selected.firstIndex(of: item.id) { selected.remove(at: i) } else { selected.append(item.id) }
    }

    /// Junta as imagens selecionadas (ordem de seleção) em um PNG: copia para o clipboard ou salva.
    private func combine(copy: Bool) {
        let urls = selected.compactMap { id in store.items.first { $0.id == id } }.compactMap { store.url(for: $0) }
        guard let data = Composer.stack(urls) else { return }
        if copy {
            onCopyImageData(data)
            Toast.show(L("%@ imagens combinadas e copiadas", String(urls.count)), symbol: "doc.on.doc")
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            panel.nameFieldStringValue = L("Montagem") + " \(f.string(from: Date())).png"
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let dest = panel.url else { return }
            do { try data.write(to: dest); Toast.show(L("Exportado: %@", dest.lastPathComponent), symbol: "square.and.arrow.down") }
            catch { Toast.show(L("Falha ao exportar: %@", error.localizedDescription), symbol: "exclamationmark.triangle.fill") }
        }
    }

    private func empty(_ msg: String) -> some View {
        Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ImageCard: View {
    let item: Item
    let store: Store
    var onDescribe: (Item) -> Void
    var onOCR: (Item) -> Void
    var onCopy: (Item) -> Void
    var onShare: (Item) -> Void
    var onRevoke: (Item) -> Void
    var onCopyText: (String) -> Void
    var selectionIndex: Int?
    var onToggleSelect: () -> Void
    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Color.secondary.opacity(0.12)
                if let thumb { Image(nsImage: thumb).resizable().scaledToFit() }
                // Círculo de seleção: clique marca/desmarca; o número mostra a ordem na montagem.
                Button(action: onToggleSelect) {
                    ZStack {
                        Circle().fill(selectionIndex == nil ? Color.black.opacity(0.35) : Color.accentColor)
                        Circle().strokeBorder(.white, lineWidth: 1.5)
                        if let i = selectionIndex { Text("\(i + 1)").font(.caption2.bold()).foregroundStyle(.white) }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .padding(6)
                .help(L("Selecionar para montagem"))
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: selectionIndex == nil ? 0 : 2.5))
            .onTapGesture(count: 2) { if let u = store.url(for: item) { NSWorkspace.shared.open(u) } }
            .onTapGesture(count: 1) { onToggleSelect() }
            if let link = item.shareURL {
                HStack(spacing: 6) {
                    Image(systemName: "link").foregroundStyle(.tint)
                    Text(link.replacingOccurrences(of: "https://", with: "")).lineLimit(1).truncationMode(.middle)
                    Text("· \(expiryText(item.shareExpires))").foregroundStyle(.secondary)
                    if item.shareOnce == true {
                        Text("1×")
                            .foregroundStyle(.orange)
                            .help(L("Visualização única — o link se apaga na primeira abertura"))
                    }
                    Spacer()
                    Button { onCopyText(link) } label: { Image(systemName: "doc.on.doc") }.help(L("Copiar link"))
                    Button { if let u = URL(string: link) { NSWorkspace.shared.open(u) } } label: { Image(systemName: "safari") }.help(L("Abrir no navegador"))
                    Button(role: .destructive) { onRevoke(item) } label: { Image(systemName: "link.badge.plus").symbolRenderingMode(.hierarchical) }.help(L("Revogar link"))
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .padding(.horizontal, 2)
            }
            HStack {
                Text("\(item.kind == .screenshot ? "Screenshot" : "Clipboard") · \(item.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale)))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { onCopy(item) } label: { Image(systemName: "doc.on.doc") }.help(L("Copiar imagem"))
                if item.shareURL == nil {
                    Button { onShare(item) } label: { Image(systemName: "link") }.help(L("Compartilhar por link público"))
                }
                Button { onDescribe(item) } label: { Image(systemName: "sparkles") }.help(L("Descrever com IA"))
                Button { onOCR(item) } label: { Image(systemName: "text.viewfinder") }.help(L("Extrair texto (OCR)"))
                Button { Exporter.export(item, store: store) } label: { Image(systemName: "square.and.arrow.up") }.help(L("Exportar…"))
                Button { if let u = store.url(for: item) { NSWorkspace.shared.activateFileViewerSelecting([u]) } } label: { Image(systemName: "folder") }.help(L("Mostrar no Finder"))
                Button { store.remove(item) } label: { Image(systemName: "trash") }.help(L("Apagar"))
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .task {
            if let u = store.url(for: item) {
                thumb = await Task.detached { loadThumbnail(u) }.value
            }
        }
    }
}


private struct TextRow: View {
    let item: Item
    let store: Store
    var onCopy: (String) -> Void
    @State private var expanded = false

    private var label: String {
        switch item.kind {
        case .ocr: return "OCR"
        case .ai: return L("IA · %@", item.source ?? "")
        default: return "Clipboard"
        }
    }
    private var symbol: String {
        switch item.kind {
        case .ocr: return "text.viewfinder"
        case .ai: return "sparkles"
        default: return "doc.on.clipboard"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.text ?? "").lineLimit(expanded ? nil : 4).textSelection(.enabled)
                Text("\(label) · \(item.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onTapGesture { expanded.toggle() }
            Spacer()
            Button { onCopy(item.text ?? "") } label: { Image(systemName: "doc.on.doc") }
                .help(L("Copiar")).buttonStyle(.borderless)
            Button { Exporter.export(item, store: store) } label: { Image(systemName: "square.and.arrow.up") }
                .help(L("Exportar como .txt")).buttonStyle(.borderless)
            Button { store.remove(item) } label: { Image(systemName: "trash") }
                .help(L("Apagar")).buttonStyle(.borderless)
        }
        .padding(.vertical, 3)
    }
}

private struct VideoCard: View {
    let item: Item
    let store: Store
    var onPlay: (Item) -> Void
    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.secondary.opacity(0.12)
                if let thumb { Image(nsImage: thumb).resizable().scaledToFit() }
                Image(systemName: "play.circle.fill").font(.system(size: 36)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 3)
                VStack { Spacer(); HStack { Spacer()
                    Text(formatDuration(item.duration ?? 0)).font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white)
                }.padding(6) }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture { onPlay(item) }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Gravação · %@", item.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale))))
                    Text(item.source ?? "").foregroundStyle(.tertiary)
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { onPlay(item) } label: { Image(systemName: "play.fill") }.help(L("Reproduzir"))
                Button { Exporter.export(item, store: store) } label: { Image(systemName: "square.and.arrow.up") }.help(L("Exportar…"))
                Button { if let u = store.url(for: item) { NSWorkspace.shared.activateFileViewerSelecting([u]) } } label: { Image(systemName: "folder") }.help(L("Mostrar no Finder"))
                Button { store.remove(item) } label: { Image(systemName: "trash") }.help(L("Apagar"))
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .task {
            if let u = store.url(for: item) { thumb = await loadVideoThumbnail(u) }
        }
    }
}
