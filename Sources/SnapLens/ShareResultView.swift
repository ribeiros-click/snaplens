import SwiftUI

/// Janela mostrada após o upload: link público + token de exclusão.
struct ShareResultView: View {
    let url: String
    let expires: Date?
    let token: String
    var onClose: () -> Void
    @State private var showToken = false
    @State private var copied = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Link pronto para compartilhar", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Link público")
                    .font(.caption).foregroundStyle(.secondary)
                Text(url)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Button { copy(url, label: "link") } label: { Label("Copiar link", systemImage: "doc.on.doc") }
                    Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: { Label("Abrir", systemImage: "safari") }
                    Spacer()
                    Text(expiresText)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Token de exclusão")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(showToken ? token : String(repeating: "•", count: min(token.count, 32)))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button { showToken.toggle() } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showToken ? "Ocultar token" : "Mostrar token")
                    Button { copy(token, label: "token") } label: { Label("Copiar token", systemImage: "doc.on.doc") }
                        .controlSize(.small)
                }
                Text("Guarde este token. Sem ele, não é possível apagar o link fora deste app.")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                if !copied.isEmpty {
                    Text(copied).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var expiresText: String {
        guard let expires else { return "Sem expiração definida" }
        return "Expira em " + expires.formatted(date: .abbreviated, time: .shortened)
    }

    private func copy(_ text: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copied = "\(label.capitalized) copiado ✓"
    }
}
