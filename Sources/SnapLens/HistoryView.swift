import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var store: Store
    var onDescribe: (Item) -> Void
    var onOCR: (Item) -> Void
    var onCopyImage: (Item) -> Void
    var onCopyText: (String) -> Void
    var onPlay: (Item) -> Void

    enum Tab: String, CaseIterable { case images = "Imagens", videos = "Vídeos", texts = "Texto" }
    @State private var tab: Tab = .images
    @State private var query = ""

    private var images: [Item] { store.items.filter { $0.kind.isImage } }
    private var videos: [Item] { store.items.filter { $0.kind == .video } }
    private var texts: [Item] {
        store.items.filter { $0.kind.isText && (query.isEmpty || ($0.text ?? "").localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                if tab == .texts {
                    TextField("Buscar…", text: $query).textFieldStyle(.roundedBorder)
                }
                Spacer()
                Button { Exporter.exportAll(store: store) } label: {
                    Label("Exportar tudo…", systemImage: "square.and.arrow.up.on.square")
                }
                Button(role: .destructive) {
                    switch tab {
                    case .images: store.clear { $0.isImage }
                    case .videos: store.clear { $0 == .video }
                    case .texts: store.clear { $0.isText }
                    }
                } label: {
                    Label("Limpar", systemImage: "trash")
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
            if images.isEmpty { empty("Nenhum screenshot ainda.\nUse \(ShortcutAction.region.shortcut.display) para capturar uma seleção.") }
            else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(images) { item in ImageCard(item: item, store: store, onDescribe: onDescribe, onOCR: onOCR, onCopy: onCopyImage) }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var videoGrid: some View {
        Group {
            if videos.isEmpty { empty("Nenhuma gravação ainda.\nUse \(ShortcutAction.record.shortcut.display) para gravar a tela.") }
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
            if texts.isEmpty { empty("Nenhum texto no histórico.") }
            else {
                List(texts) { item in
                    TextRow(item: item, store: store, onCopy: onCopyText)
                }
            }
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
    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.secondary.opacity(0.12)
                if let thumb { Image(nsImage: thumb).resizable().scaledToFit() }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(count: 2) { if let u = store.url(for: item) { NSWorkspace.shared.open(u) } }
            HStack {
                Text("\(item.kind == .screenshot ? "Screenshot" : "Clipboard") · \(item.date.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { onCopy(item) } label: { Image(systemName: "doc.on.doc") }.help("Copiar imagem")
                Button { onDescribe(item) } label: { Image(systemName: "sparkles") }.help("Descrever com IA")
                Button { onOCR(item) } label: { Image(systemName: "text.viewfinder") }.help("Extrair texto (OCR)")
                Button { Exporter.export(item, store: store) } label: { Image(systemName: "square.and.arrow.up") }.help("Exportar…")
                Button { if let u = store.url(for: item) { NSWorkspace.shared.activateFileViewerSelecting([u]) } } label: { Image(systemName: "folder") }.help("Mostrar no Finder")
                Button { store.remove(item) } label: { Image(systemName: "trash") }.help("Apagar")
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
        case .ai: return "IA · \(item.source ?? "")"
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
                Text("\(label) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onTapGesture { expanded.toggle() }
            Spacer()
            Button { onCopy(item.text ?? "") } label: { Image(systemName: "doc.on.doc") }
                .help("Copiar").buttonStyle(.borderless)
            Button { Exporter.export(item, store: store) } label: { Image(systemName: "square.and.arrow.up") }
                .help("Exportar como .txt").buttonStyle(.borderless)
            Button { store.remove(item) } label: { Image(systemName: "trash") }
                .help("Apagar").buttonStyle(.borderless)
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
                    Text("Gravação · \(item.date.formatted(date: .abbreviated, time: .shortened))")
                    Text(item.source ?? "").foregroundStyle(.tertiary)
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { onPlay(item) } label: { Image(systemName: "play.fill") }.help("Reproduzir")
                Button { Exporter.export(item, store: store) } label: { Image(systemName: "square.and.arrow.up") }.help("Exportar…")
                Button { if let u = store.url(for: item) { NSWorkspace.shared.activateFileViewerSelecting([u]) } } label: { Image(systemName: "folder") }.help("Mostrar no Finder")
                Button { store.remove(item) } label: { Image(systemName: "trash") }.help("Apagar")
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
