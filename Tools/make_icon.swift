import AppKit

// Gera o ícone 1024x1024. Uso: make_icon <saida.png> [1|2|3]
//   1 = Lente   (anel de lente + ponto de gravação, azul/ciano)
//   2 = Foco    (moldura de captura + play, laranja/magenta)
//   3 = Grafite (moldura menta + botão REC, escuro)
let S: CGFloat = 1024
let variant = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1 : 1
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let body = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let center = NSPoint(x: S / 2, y: S / 2)

// Sombra suave do corpo
NSGraphicsContext.saveGraphicsState()
let sh = NSShadow()
sh.shadowColor = c(0, 0, 0, 0.35); sh.shadowBlurRadius = 28; sh.shadowOffset = NSSize(width: 0, height: -12)
sh.set()
c(0, 0, 0, 1).setFill(); body.fill()
NSGraphicsContext.restoreGraphicsState()

func brackets(in frame: NSRect, len L: CGFloat, width: CGFloat, color: NSColor) {
    color.setStroke()
    let p = NSBezierPath()
    p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
    let (x0, y0, x1, y1) = (frame.minX, frame.minY, frame.maxX, frame.maxY)
    p.move(to: NSPoint(x: x0, y: y0 + L)); p.line(to: NSPoint(x: x0, y: y0)); p.line(to: NSPoint(x: x0 + L, y: y0))
    p.move(to: NSPoint(x: x1 - L, y: y0)); p.line(to: NSPoint(x: x1, y: y0)); p.line(to: NSPoint(x: x1, y: y0 + L))
    p.move(to: NSPoint(x: x1, y: y1 - L)); p.line(to: NSPoint(x: x1, y: y1)); p.line(to: NSPoint(x: x1 - L, y: y1))
    p.move(to: NSPoint(x: x0 + L, y: y1)); p.line(to: NSPoint(x: x0, y: y1)); p.line(to: NSPoint(x: x0, y: y1 - L))
    p.stroke()
}
func circle(_ r: CGFloat, at p: NSPoint = center) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
}

NSGraphicsContext.saveGraphicsState()
body.addClip()

switch variant {
case 2:
    NSGradient(colors: [c(1.0, 0.62, 0.12), c(0.98, 0.25, 0.42), c(0.75, 0.16, 0.62)])!.draw(in: rect, angle: -55)
    let frame = rect.insetBy(dx: 150, dy: 150)
    brackets(in: frame, len: 135, width: 48, color: .white)
    // triângulo de play com cantos arredondados
    let t = NSBezierPath()
    t.lineJoinStyle = .round; t.lineWidth = 40
    let r: CGFloat = 105
    let pts = [NSPoint(x: center.x - r * 0.7 + 12, y: center.y + r), NSPoint(x: center.x - r * 0.7 + 12, y: center.y - r),
               NSPoint(x: center.x + r * 1.1 + 12, y: center.y)]
    t.move(to: pts[0]); t.line(to: pts[1]); t.line(to: pts[2]); t.close()
    c(1, 1, 1).setFill(); c(1, 1, 1).setStroke(); t.fill(); t.stroke()
case 3:
    NSGradient(colors: [c(0.17, 0.18, 0.21), c(0.06, 0.06, 0.08)])!.draw(in: rect, angle: -70)
    let frame = rect.insetBy(dx: 150, dy: 150)
    brackets(in: frame, len: 135, width: 46, color: c(0.30, 0.95, 0.74))
    // brilho do botão REC
    NSGradient(colors: [c(1, 0.2, 0.25, 0.55), c(1, 0.2, 0.25, 0)])!
        .draw(in: circle(230), relativeCenterPosition: .zero)
    NSGradient(colors: [c(1, 0.45, 0.42), c(0.92, 0.12, 0.2)])!.draw(in: circle(118), angle: -90)
    c(1, 1, 1, 0.9).setStroke()
    let ring = circle(158); ring.lineWidth = 16; ring.stroke()
default:
    NSGradient(colors: [c(0.10, 0.62, 0.95), c(0.30, 0.25, 0.85), c(0.12, 0.08, 0.40)])!.draw(in: rect, angle: -60)
    // anel externo da lente
    c(1, 1, 1, 0.95).setStroke()
    let outer = circle(285); outer.lineWidth = 52; outer.stroke()
    // vidro
    NSGradient(colors: [c(0.10, 0.12, 0.35), c(0.02, 0.03, 0.14)])!.draw(in: circle(250), relativeCenterPosition: NSPoint(x: -0.3, y: 0.3))
    c(0.45, 0.85, 1.0, 0.85).setStroke()
    let mid = circle(150); mid.lineWidth = 22; mid.stroke()
    NSGradient(colors: [c(0.3, 0.8, 1.0, 0.9), c(0.3, 0.5, 1.0, 0.35)])!.draw(in: circle(78), angle: -45)
    // reflexo
    c(1, 1, 1, 0.38).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 190, y: center.y + 70, width: 120, height: 62)).fill()
    // ponto de gravação
    let dot = NSPoint(x: center.x + 250, y: center.y - 250)
    c(1, 1, 1).setFill(); circle(66, at: dot).fill()
    c(0.95, 0.15, 0.22).setFill(); circle(48, at: dot).fill()
}
// Brilho superior sutil
NSGradient(colors: [c(1, 1, 1, 0.18), c(1, 1, 1, 0)])!.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
