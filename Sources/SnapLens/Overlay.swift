import AppKit

enum ShotAction { case copy, save, ocr, describe, share }

enum Tool: Int, CaseIterable {
    case rect, ellipse, line, arrow, pen, text
    var symbol: String {
        switch self {
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        }
    }
    var title: String {
        switch self {
        case .rect: return "Retângulo"
        case .ellipse: return "Elipse"
        case .line: return "Linha"
        case .arrow: return "Seta"
        case .pen: return "Caneta"
        case .text: return "Texto"
        }
    }
}

struct Annotation {
    var tool: Tool
    var color: NSColor
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var text: String = ""
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Fecha TODA janela de overlay existente, mesmo que alguma referência tenha se perdido.
    /// É a garantia final contra "tela presa": qualquer caminho de cancelamento passa por aqui.
    @MainActor static func closeAll() {
        let n = NSApp.windows.filter { $0 is OverlayWindow && $0.isVisible }.count
        if n > 0 { Trace.log("OverlayWindow.closeAll: \(n) janela(s) visível(is)") }
        for w in NSApp.windows where w is OverlayWindow {
            w.orderOut(nil)
            w.contentView = nil
        }
    }
    @MainActor static var anyVisible: Bool { NSApp.windows.contains { $0 is OverlayWindow && $0.isVisible } }
}

/// Apresenta a tela congelada para seleção de área + anotações (estilo Lightshot).
@MainActor
final class CaptureOverlay {
    private var window: OverlayWindow?
    private var view: OverlayView?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var watchdog: Timer?
    private var lastActivity = Date()
    private static let escapeHotKeyID: UInt32 = 99

    var isActive: Bool { window != nil || OverlayWindow.anyVisible }

    func present(screen: NSScreen, image: CGImage, autoAction: ShotAction?,
                 onFinish: @escaping (ShotAction, Data) -> Void) {
        Trace.log("present: screen=\(screen.frame) image=\(image.width)x\(image.height) auto=\(String(describing: autoAction)) active=\(NSApp.isActive)")
        dismiss(reason: "present") // nunca empilha dois overlays
        let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        // Abaixo da barra de menus e do Dock: o usuário nunca fica sem saída (Cmd-Tab, Dock e menu continuam acessíveis).
        w.level = .floating
        w.isOpaque = true
        w.hasShadow = false
        w.backgroundColor = .black
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.acceptsMouseMovedEvents = true // necessário para o timeout de inatividade enxergar o mouse

        let v = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image, autoAction: autoAction)
        // Captura a própria janela: fecha mesmo se `self.window` já tiver sido zerado por outro caminho.
        v.onFinish = { [weak self, weak w] action, data in
            Trace.log("onFinish: action=\(action) data=\(data?.count ?? 0)B")
            self?.dismiss(reason: "onFinish")
            w?.orderOut(nil)
            OverlayWindow.closeAll()
            if let data { onFinish(action, data) }
        }
        w.contentView = v
        window = w
        view = v

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        w.makeFirstResponder(v)
        Trace.log("present: janela visível=\(w.isVisible) key=\(w.isKeyWindow) appActive=\(NSApp.isActive) firstResponder=\(w.firstResponder === v)")

        // Saída de emergência: Esc global (não depende de a janela ter o foco do teclado).
        HotKeys.register(id: Self.escapeHotKeyID, keyCode: 53, modifiers: 0) { [weak self] in
            Trace.log("hotkey Esc global: view=\(self?.view != nil)")
            if let v = self?.view { v.handleEscape() } else { self?.dismiss(reason: "esc-sem-view") }
        }
        // Mudança na configuração de telas invalida a geometria: fecha. (Perder o foco NÃO fecha mais:
        // isso disparava durante a abertura e deixava uma janela órfã impossível de fechar.)
        observers = [
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss(reason: "screenParametersChanged") }
            },
        ]

        // Fecha sozinho após 60s sem nenhuma interação (último recurso contra travar a tela).
        lastActivity = Date()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .mouseMoved]) { [weak self] e in
            MainActor.assumeIsolated { self?.lastActivity = Date() }
            return e
        }
        // Sem seleção: 10 s sem mexer o mouse ou teclar encerra a captura. Com seleção: 60 s.
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let view = self.view else { OverlayWindow.closeAll(); return }
                let idle = Date().timeIntervalSince(self.lastActivity)
                let limit: TimeInterval = view.hasSelection ? 60 : 10
                view.idleCountdown = view.hasSelection ? nil : max(0, Int((limit - idle).rounded(.up)))
                if idle > limit { self.dismiss(reason: "inatividade-\(Int(limit))s") }
            }
        }
    }

    /// Render offscreen do overlay (usado por `--render-shots` para os prints do site).
    static func preview(background: CGImage, size: CGSize, selection: CGRect) -> NSView {
        let v = OverlayView(frame: CGRect(origin: .zero, size: size), image: background, autoAction: nil)
        v.installPreview(selection: selection)
        return v
    }

    func dismiss(reason: String = "unspecified") {
        if window != nil || OverlayWindow.anyVisible { Trace.log("dismiss(\(reason)): window=\(window != nil) anyVisible=\(OverlayWindow.anyVisible)") }
        HotKeys.unregister(id: Self.escapeHotKeyID)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        watchdog?.invalidate(); watchdog = nil
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        OverlayWindow.closeAll()
        view = nil
    }
}

@MainActor
private final class OverlayView: NSView, NSTextFieldDelegate {
    private let cgImage: CGImage
    private let background: NSImage
    private let autoAction: ShotAction?
    var onFinish: ((ShotAction, Data?) -> Void)?

    private var selection: CGRect?
    var hasSelection: Bool { selection != nil }
    /// Segundos restantes até o fechamento automático (só sem seleção); nil = não mostrar.
    var idleCountdown: Int? { didSet { if idleCountdown != oldValue { needsDisplay = true } } }
    private var annotations: [Annotation] = []
    private var tool: Tool?
    private var color: NSColor = .systemRed
    private let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .white, .black]

    private enum Mode { case idle, creating(CGPoint), moving(CGPoint), resizing(Handle), drawing }
    private enum Handle: CaseIterable { case tl, t, tr, r, br, b, bl, l }
    private var mode: Mode = .idle
    private var toolbar: NSVisualEffectView?
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, image: CGImage, autoAction: ShotAction?) {
        cgImage = image
        background = NSImage(cgImage: image, size: frame.size)
        self.autoAction = autoAction
        super.init(frame: frame)
        let cancel = NSButton(title: "✕  Cancelar  (Esc)", target: self, action: #selector(doCancel))
        cancel.bezelStyle = .rounded
        cancel.controlSize = .large
        cancel.sizeToFit()
        cancel.frame.origin = CGPoint(x: frame.midX - cancel.frame.width / 2, y: 16)
        addSubview(cancel)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let dim = NSBezierPath(rect: bounds)
        if let s = selection {
            dim.append(NSBezierPath(rect: s))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        guard let s = selection else {
            let timer = idleCountdown.map { " · fecha sozinho em \($0)s" } ?? ""
            drawText("Arraste para selecionar · botão direito refaz · Esc cancela\(timer)", at: CGPoint(x: bounds.midX, y: 64), centered: true)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: s).addClip()
        annotations.forEach(Self.draw)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: s)
        border.lineWidth = 1
        border.stroke()

        NSColor.white.setFill()
        for h in Handle.allCases {
            let p = point(of: h, in: s)
            let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            NSBezierPath(ovalIn: r).fill()
            NSColor.systemBlue.setStroke()
            NSBezierPath(ovalIn: r).stroke()
        }
        let label = "\(Int(s.width)) × \(Int(s.height))"
        drawText(label, at: CGPoint(x: s.minX, y: max(s.minY - 24, 4)), centered: false)
    }

    private func drawText(_ text: String, at p: CGPoint, centered: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let box = CGRect(x: centered ? p.x - size.width / 2 - 8 : p.x, y: p.y, width: size.width + 16, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        str.draw(at: CGPoint(x: box.minX + 8, y: box.minY + 3))
    }

    static func draw(_ a: Annotation) {
        a.color.setStroke()
        a.color.setFill()
        if a.tool == .text {
            NSAttributedString(string: a.text, attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .bold),
                                                            .foregroundColor: a.color]).draw(at: CGPoint(x: a.start.x + 2, y: a.start.y))
            return
        }
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let rect = CGRect(x: min(a.start.x, a.end.x), y: min(a.start.y, a.end.y),
                          width: abs(a.start.x - a.end.x), height: abs(a.start.y - a.end.y))
        switch a.tool {
        case .rect: path.appendRect(rect)
        case .ellipse: path.appendOval(in: rect)
        case .line:
            path.move(to: a.start); path.line(to: a.end)
        case .arrow:
            path.move(to: a.start); path.line(to: a.end)
            let angle = atan2(a.end.y - a.start.y, a.end.x - a.start.x)
            let len: CGFloat = 18, spread: CGFloat = .pi / 7
            let p1 = CGPoint(x: a.end.x - len * cos(angle - spread), y: a.end.y - len * sin(angle - spread))
            let p2 = CGPoint(x: a.end.x - len * cos(angle + spread), y: a.end.y - len * sin(angle + spread))
            let head = NSBezierPath()
            head.move(to: a.end); head.line(to: p1); head.line(to: p2); head.close()
            head.fill()
        case .text: break
        case .pen:
            if let first = a.points.first {
                path.move(to: first)
                a.points.dropFirst().forEach { path.line(to: $0) }
            }
        }
        path.stroke()
    }

    // MARK: Geometry

    private func point(of h: Handle, in r: CGRect) -> CGPoint {
        switch h {
        case .tl: return CGPoint(x: r.minX, y: r.minY)
        case .t: return CGPoint(x: r.midX, y: r.minY)
        case .tr: return CGPoint(x: r.maxX, y: r.minY)
        case .r: return CGPoint(x: r.maxX, y: r.midY)
        case .br: return CGPoint(x: r.maxX, y: r.maxY)
        case .b: return CGPoint(x: r.midX, y: r.maxY)
        case .bl: return CGPoint(x: r.minX, y: r.maxY)
        case .l: return CGPoint(x: r.minX, y: r.midY)
        }
    }

    private func handle(at p: CGPoint) -> Handle? {
        guard let s = selection else { return nil }
        return Handle.allCases.first { hypot(point(of: $0, in: s).x - p.x, point(of: $0, in: s).y - p.y) <= 9 }
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func resize(_ r: CGRect, handle h: Handle, to p: CGPoint) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch h {
        case .tl: minX = p.x; minY = p.y
        case .t: minY = p.y
        case .tr: maxX = p.x; minY = p.y
        case .r: maxX = p.x
        case .br: maxX = p.x; maxY = p.y
        case .b: maxY = p.y
        case .bl: minX = p.x; maxY = p.y
        case .l: minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = clamp(convert(event.locationInWindow, from: nil))
        Trace.log("mouseDown p=\(Int(p.x)),\(Int(p.y)) sel=\(selection.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil") tool=\(String(describing: tool)) mode=\(mode)")
        if let s = selection {
            if tool == .text, s.contains(p) {
                beginText(at: p)
                return
            }
            if let t = tool, s.contains(p) {
                annotations.append(Annotation(tool: t, color: color, start: p, end: p, points: [p]))
                mode = .drawing
                return
            }
            if let h = handle(at: p) { mode = .resizing(h); hideToolbar(); return }
            if s.contains(p) { mode = .moving(CGPoint(x: p.x - s.minX, y: p.y - s.minY)); hideToolbar(); return }
        }
        selection = nil
        annotations.removeAll()
        hideToolbar()
        mode = .creating(p)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = clamp(convert(event.locationInWindow, from: nil))
        switch mode {
        case .creating(let origin):
            selection = rect(origin, p)
        case .moving(let off):
            if let s = selection {
                var x = p.x - off.x, y = p.y - off.y
                x = min(max(x, 0), bounds.width - s.width)
                y = min(max(y, 0), bounds.height - s.height)
                selection = CGRect(x: x, y: y, width: s.width, height: s.height)
            }
        case .resizing(let h):
            if let s = selection { selection = resize(s, handle: h, to: p) }
        case .drawing:
            if var a = annotations.popLast() {
                a.end = p
                if a.tool == .pen { a.points.append(p) }
                annotations.append(a)
            }
        case .idle: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        Trace.log("mouseUp mode=\(mode) sel=\(selection.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil")")
        defer { mode = .idle; needsDisplay = true }
        guard let s = selection else { return }
        if s.width < 4 || s.height < 4 {
            selection = nil
            return
        }
        if case .drawing = mode { return }
        if let auto = autoAction { finish(auto); return }
        showToolbar()
    }

    // MARK: Cancelamento

    func handleEscape() {
        Trace.log("handleEscape textField=\(textField != nil)")
        if textField != nil {
            textField?.stringValue = ""
            commitText()
        } else {
            onFinish?(.copy, nil)
        }
    }

    private func resetSelection() {
        commitText()
        selection = nil
        annotations.removeAll()
        hideToolbar()
        mode = .idle
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if selection != nil { resetSelection() } else { onFinish?(.copy, nil) }
    }

    @objc private func doReselect() { resetSelection() }

    // MARK: Text tool

    private var textField: NSTextField?

    private func beginText(at p: CGPoint) {
        commitText()
        let f = NSTextField(frame: CGRect(x: p.x, y: p.y - 4, width: 240, height: 28))
        f.isBordered = false
        f.isBezeled = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 20, weight: .bold)
        f.textColor = color
        f.placeholderString = "Digite…"
        f.delegate = self
        addSubview(f)
        textField = f
        window?.makeFirstResponder(f)
    }

    private func commitText() {
        guard let f = textField else { return }
        textField = nil
        let text = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        f.delegate = nil
        f.removeFromSuperview()
        if !text.isEmpty {
            let origin = CGPoint(x: f.frame.minX, y: f.frame.minY + 4)
            annotations.append(Annotation(tool: .text, color: color, start: origin, end: origin, text: text))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { commitText(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""
            commitText()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        Trace.log("keyDown code=\(event.keyCode) mods=\(event.modifierFlags.rawValue)")
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: handleEscape()                                 // Esc
        case 36, 76: if selection != nil { finish(.copy) }       // Return
        case 123, 124, 125, 126: nudge(event)
        default:
            if cmd, let c = event.charactersIgnoringModifiers {
                if c == "z" { undo() }
                else if c == "c", selection != nil { finish(.copy) }
                else if c == "s", selection != nil { finish(.save) }
            }
        }
    }

    private func nudge(_ event: NSEvent) {
        guard var s = selection else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: s.origin.x -= step
        case 124: s.origin.x += step
        case 125: s.origin.y += step
        default: s.origin.y -= step
        }
        s.origin.x = min(max(s.origin.x, 0), bounds.width - s.width)
        s.origin.y = min(max(s.origin.y, 0), bounds.height - s.height)
        selection = s
        positionToolbar()
        needsDisplay = true
    }

    @objc private func undo() {
        _ = annotations.popLast()
        needsDisplay = true
    }

    // MARK: Toolbar

    private func hideToolbar() { toolbar?.isHidden = true }

    private func showToolbar() {
        if toolbar == nil { buildToolbar() }
        toolbar?.isHidden = false
        positionToolbar()
    }

    private func positionToolbar() {
        guard let tb = toolbar, let s = selection else { return }
        let size = tb.frame.size
        var x = s.maxX - size.width
        x = min(max(x, 8), bounds.width - size.width - 8)
        var y = s.maxY + 10
        if y + size.height > bounds.height - 8 { y = s.minY - size.height - 10 }
        if y < 8 { y = s.maxY - size.height - 10 }
        tb.frame.origin = CGPoint(x: x, y: y)
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector, tag: Int = 0) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(),
                         target: self, action: action)
        b.isBordered = false
        b.toolTip = tip
        b.tag = tag
        b.imageScaling = .scaleProportionallyDown
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }

    private func buildToolbar() {
        var views: [NSView] = []
        toolButtons = Tool.allCases.map { button($0.symbol, $0.title, #selector(pickTool(_:)), tag: $0.rawValue) }
        views += toolButtons
        views.append(separator())
        colorButtons = palette.enumerated().map { i, _ in
            let b = NSButton(title: "", target: self, action: #selector(pickColor(_:)))
            b.isBordered = false; b.tag = i
            b.widthAnchor.constraint(equalToConstant: 20).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return b
        }
        views += colorButtons
        views.append(separator())
        views.append(button("arrow.uturn.backward", "Desfazer (⌘Z)", #selector(undo)))
        views.append(separator())
        views.append(button("sparkles", "Descrever com IA", #selector(doDescribe)))
        views.append(button("text.viewfinder", "Extrair texto (OCR)", #selector(doOCR)))
        views.append(button("link", "Compartilhar por link público", #selector(doShare)))
        views.append(button("square.and.arrow.down", "Salvar (⌘S)", #selector(doSave)))
        views.append(button("doc.on.doc", "Copiar (⌘C / Enter)", #selector(doCopy)))
        views.append(button("rectangle.dashed", "Refazer seleção (botão direito)", #selector(doReselect)))
        views.append(button("xmark", "Cancelar captura (Esc)", #selector(doCancel)))

        let stack = NSStackView(views: views)
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 10
        fx.layer?.masksToBounds = true
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor),
            stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        fx.frame = CGRect(origin: .zero, size: stack.fittingSize)
        addSubview(fx)
        toolbar = fx
        refreshToolbarState()
    }

    private func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return v
    }

    private func refreshToolbarState() {
        for b in toolButtons { b.contentTintColor = (tool?.rawValue == b.tag) ? .controlAccentColor : .labelColor }
        for b in colorButtons {
            let c = palette[b.tag]
            let selected = c == color
            let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
                let dot = r.insetBy(dx: selected ? 2 : 3, dy: selected ? 2 : 3)
                c.setFill(); NSBezierPath(ovalIn: dot).fill()
                NSColor.gray.withAlphaComponent(0.6).setStroke()
                let o = NSBezierPath(ovalIn: dot); o.lineWidth = 0.5; o.stroke()
                if selected {
                    NSColor.controlAccentColor.setStroke()
                    let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75)); ring.lineWidth = 1.5; ring.stroke()
                }
                return true
            }
            b.image = img
        }
    }

    @objc private func pickTool(_ sender: NSButton) {
        let t = Tool(rawValue: sender.tag)
        tool = (tool == t) ? nil : t
        refreshToolbarState()
    }

    @objc private func pickColor(_ sender: NSButton) {
        color = palette[sender.tag]
        if tool == nil { tool = .arrow }
        refreshToolbarState()
    }

    @objc private func doCopy() { finish(.copy) }
    @objc private func doSave() { finish(.save) }
    @objc private func doOCR() { finish(.ocr) }
    @objc private func doDescribe() { finish(.describe) }
    @objc private func doShare() { finish(.share) }

    /// Estado de demonstração (prints do site): seleção, anotações e barra visíveis.
    func installPreview(selection s: CGRect) {
        selection = s
        annotations = [
            Annotation(tool: .rect, color: .systemRed, start: CGPoint(x: s.minX + 24, y: s.minY + 60), end: CGPoint(x: s.minX + 300, y: s.minY + 110)),
            Annotation(tool: .arrow, color: .systemOrange, start: CGPoint(x: s.maxX - 60, y: s.maxY - 40), end: CGPoint(x: s.minX + 310, y: s.minY + 90)),
            Annotation(tool: .text, color: .systemOrange, start: CGPoint(x: s.maxX - 150, y: s.maxY - 36), end: .zero, text: "Revisar aqui"),
        ]
        tool = .arrow
        color = .systemOrange
        showToolbar()
    }
    @objc private func doCancel() { onFinish?(.copy, nil) }

    // MARK: Output

    private func finish(_ action: ShotAction) {
        Trace.log("finish(\(action)) sel=\(selection.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil") annotations=\(annotations.count)")
        commitText()
        onFinish?(action, renderSelection(annotated: action != .ocr && action != .describe))
    }

    private func renderSelection(annotated: Bool) -> Data? {
        guard let s = selection else { return nil }
        let scale = CGFloat(cgImage.width) / bounds.width
        let pw = Int((s.width * scale).rounded()), ph = Int((s.height * scale).rounded())
        guard pw > 0, ph > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = base.cgContext
        cg.translateBy(x: 0, y: CGFloat(ph))
        cg.scaleBy(x: pw == 0 ? 1 : CGFloat(pw) / s.width, y: -CGFloat(ph) / s.height)
        cg.translateBy(x: -s.minX, y: -s.minY)
        let ctx = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        background.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        if annotated { annotations.forEach(Self.draw) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
