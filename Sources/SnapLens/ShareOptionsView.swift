import SwiftUI
import AppKit

/// Escolha de validade feita na hora de compartilhar.
enum ShareChoice: String, CaseIterable {
    case once, d1, d5, custom, never

    var title: String {
        switch self {
        case .once: return L("Ver uma vez")
        case .d1: return L("Durante 1 dia")
        case .d5: return L("Durante 5 dias")
        case .custom: return L("Durante…")
        case .never: return L("Nunca expirar")
        }
    }

    /// (segundos de validade, visualização única). "Ver uma vez" tem 30 dias como vida máxima.
    func resolve(customDays: Int) -> (seconds: Int, once: Bool) {
        switch self {
        case .once: return (30 * 86400, true)
        case .d1: return (86400, false)
        case .d5: return (5 * 86400, false)
        case .custom: return (max(1, min(customDays, 365)) * 86400, false)
        case .never: return (0, false)
        }
    }

    static var last: ShareChoice {
        get { ShareChoice(rawValue: UserDefaults.standard.string(forKey: "share.choice") ?? "") ?? .d1 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "share.choice") }
    }
    static var customDays: Int {
        get { max(1, UserDefaults.standard.integer(forKey: "share.customDays") == 0 ? 7 : UserDefaults.standard.integer(forKey: "share.customDays")) }
        set { UserDefaults.standard.set(newValue, forKey: "share.customDays") }
    }
}

struct ShareOptionsView: View {
    var onShare: (ShareChoice, Int) -> Void
    var onCancel: () -> Void
    @State private var choice = ShareChoice.last
    @State private var days = ShareChoice.customDays

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("Compartilhar por link público"), systemImage: "link").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ShareChoice.allCases, id: \.self) { c in
                    HStack(spacing: 8) {
                        Image(systemName: choice == c ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(choice == c ? Color.accentColor : .secondary)
                        Text(c.title)
                        if c == .custom {
                            TextField("", value: $days, format: .number)
                                .frame(width: 52).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                                .onChange(of: days) { _, _ in choice = .custom }
                            Stepper("", value: $days, in: 1...365).labelsHidden()
                            Text(L("dias"))
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { choice = c }
                }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Cancelar"), role: .cancel) { onCancel() }.keyboardShortcut(.cancelAction)
                Button(L("Compartilhar")) {
                    ShareChoice.last = choice
                    ShareChoice.customDays = max(1, min(days, 365))
                    onShare(choice, ShareChoice.customDays)
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private var hint: String {
        switch choice {
        case .once: return L("O link se apaga na primeira abertura (ou em 30 dias, o que vier primeiro).")
        case .never: return L("O link fica no ar até você revogá-lo na Biblioteca ou pela página de token.")
        default: return L("Passado o prazo, a imagem é apagada do servidor. Você pode revogar antes.")
        }
    }
}
