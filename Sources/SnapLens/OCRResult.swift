import SwiftUI
import AppKit
import Translation

struct TargetLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
    static let all: [TargetLanguage] = [
        .init(code: "pt-BR", name: L("Português (Brasil)")), .init(code: "en", name: L("Inglês")),
        .init(code: "es", name: L("Espanhol")), .init(code: "fr", name: L("Francês")),
        .init(code: "de", name: L("Alemão")), .init(code: "it", name: L("Italiano")),
        .init(code: "ja", name: L("Japonês")), .init(code: "ko", name: L("Coreano")),
        .init(code: "zh-Hans", name: L("Chinês (simplificado)")),
    ]
}

struct OCRResultView: View {
    let original: String
    var onCopy: (String) -> Void

    @State private var text: String
    @State private var translated = ""
    @State private var target = TargetLanguage.all.first { $0.code == L10n.code } ?? TargetLanguage.all[0]
    @State private var busy = false
    @State private var error: String?
    @State private var appleTrigger = 0
    @State private var engine = ""

    init(original: String, onCopy: @escaping (String) -> Void) {
        self.original = original
        self.onCopy = onCopy
        _text = State(initialValue: original)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Texto reconhecido"), systemImage: "text.viewfinder").font(.headline)
                Spacer()
                Text(L("Já copiado para a área de transferência")).font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Button { onCopy(text) } label: { Label(L("Copiar"), systemImage: "doc.on.doc") }
                Spacer()
                Picker(L("Traduzir para"), selection: $target) {
                    ForEach(TargetLanguage.all) { Text($0.name).tag($0) }
                }.frame(maxWidth: 280)
                Button { translate() } label: { Label(L("Traduzir"), systemImage: "character.bubble") }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if busy { ProgressView().controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if !translated.isEmpty {
                HStack {
                    Label(L("Tradução"), systemImage: "character.bubble").font(.headline)
                    if !engine.isEmpty { Text("(\(engine))").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button { onCopy(translated) } label: { Label(L("Copiar tradução"), systemImage: "doc.on.doc") }
                }
                ScrollView { Text(translated).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(minHeight: 100)
                    .padding(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 240)
        .background {
            if #available(macOS 15.0, *) {
                AppleTranslator(text: text, target: target.code, trigger: appleTrigger) { result in
                    busy = false
                    switch result {
                    case .success(let t): translated = t; engine = "Apple"
                    case .failure(let e): error = L("Falha na tradução: %@", e.localizedDescription)
                    }
                }
            }
        }
    }

    private func translate() {
        error = nil
        busy = true
        if let provider = Provider.active {
            let src = text, lang = target.name
            Task {
                do {
                    let t = try await AIClient.translate(src, to: lang, provider: provider)
                    translated = t; engine = provider.shortName
                } catch { self.error = error.localizedDescription }
                busy = false
            }
        } else if #available(macOS 15.0, *) {
            appleTrigger += 1
        } else {
            busy = false
            error = L("Configure um provedor de IA em Ajustes para traduzir.")
        }
    }
}

@available(macOS 15.0, *)
private struct AppleTranslator: View {
    let text: String
    let target: String
    let trigger: Int
    var onResult: (Result<String, Error>) -> Void
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: trigger) {
                let c = TranslationSession.Configuration(source: nil, target: Locale.Language(identifier: target))
                if config != nil, config?.target == c.target { config?.invalidate() } else { config = c }
            }
            .translationTask(config) { session in
                do { onResult(.success(try await session.translate(text).targetText)) }
                catch { onResult(.failure(error)) }
            }
    }
}

@MainActor
enum OCRResultWindow {
    private static var window: NSWindow?

    static func show(text: String, onCopy: @escaping (String) -> Void) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "SnapLens — " + L("Resultado do OCR")
        w.contentView = NSHostingView(rootView: OCRResultView(original: text, onCopy: onCopy))
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
