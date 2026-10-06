import AppKit
import SwiftUI
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int   // máscara do Carbon (cmdKey, optionKey, controlKey, shiftKey)
    var key: String      // texto exibido da tecla

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + key
    }
    var menuMask: NSEvent.ModifierFlags {
        var m: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { m.insert(.control) }
        if modifiers & optionKey != 0 { m.insert(.option) }
        if modifiers & shiftKey != 0 { m.insert(.shift) }
        if modifiers & cmdKey != 0 { m.insert(.command) }
        return m
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case region, full, ocr, describe, record, history
    var id: String { rawValue }
    static let changed = Notification.Name("SnapLensShortcutsChanged")

    var title: String {
        switch self {
        case .region: return "Capturar seleção"
        case .full: return "Capturar tela inteira"
        case .ocr: return "OCR de uma seleção"
        case .describe: return "Descrever seleção com IA"
        case .record: return "Gravar tela (iniciar/parar)"
        case .history: return "Abrir biblioteca"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .region: return Shortcut(keyCode: kVK_ANSI_P, modifiers: cmdKey | optionKey, key: "P")
        case .full: return Shortcut(keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey, key: "F")
        case .ocr: return Shortcut(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey, key: "T")
        case .describe: return Shortcut(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey, key: "D")
        case .record: return Shortcut(keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey, key: "R")
        case .history: return Shortcut(keyCode: kVK_ANSI_H, modifiers: controlKey | optionKey, key: "H")
        }
    }

    var shortcut: Shortcut {
        get {
            if let d = UserDefaults.standard.data(forKey: "shortcut.\(rawValue)"),
               let s = try? JSONDecoder().decode(Shortcut.self, from: d) { return s }
            return defaultShortcut
        }
        nonmutating set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: "shortcut.\(rawValue)") }
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: "shortcut.\(rawValue)")
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

private func keyLabel(for event: NSEvent) -> String {
    switch Int(event.keyCode) {
    case kVK_Space: return "Space"
    case kVK_Return: return "↩"
    case kVK_Tab: return "⇥"
    case kVK_Delete: return "⌫"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"; case kVK_F4: return "F4"
    case kVK_F5: return "F5"; case kVK_F6: return "F6"; case kVK_F7: return "F7"; case kVK_F8: return "F8"
    case kVK_F9: return "F9"; case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
    default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

struct ShortcutRow: View {
    let action: ShortcutAction
    @State private var shortcut: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    init(action: ShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: action.shortcut)
    }

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            Button(recording ? "Pressione as teclas… (Esc cancela)" : shortcut.display) { recording ? stop() : start() }
                .frame(minWidth: 140)
            Button { action.reset(); shortcut = action.shortcut } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Restaurar padrão").buttonStyle(.borderless)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { stop(); return }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f.contains(.command) || f.contains(.control) || f.contains(.option) else { return } // exige modificador
        var mods = 0
        if f.contains(.command) { mods |= cmdKey }
        if f.contains(.option) { mods |= optionKey }
        if f.contains(.control) { mods |= controlKey }
        if f.contains(.shift) { mods |= shiftKey }
        let s = Shortcut(keyCode: Int(event.keyCode), modifiers: mods, key: keyLabel(for: event))
        action.shortcut = s
        shortcut = s
        stop()
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}
