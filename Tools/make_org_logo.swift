import AppKit
// Logo da organização ribeiros.click: monograma "r" em areia sobre musgo, com o ponto do ".click" em marrom.
let S: CGFloat = 1024
let out = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: a) }
let moss = c(0.373, 0.478, 0.208), sand = c(0.953, 0.933, 0.894), brown = c(0.541, 0.416, 0.235), dark = c(0.235, 0.302, 0.129)
// fundo: círculo musgo (avatares do GitHub são recortados em círculo)
moss.setFill(); NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: S, height: S)).fill()
NSGradient(colors: [c(1, 1, 1, 0.08), c(0, 0, 0, 0.10)])!.draw(in: NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: S, height: S)), angle: -90)
// "r" minúsculo geométrico: haste + arco
let stroke: CGFloat = 118
sand.setStroke()
let stem = NSBezierPath(); stem.lineWidth = stroke; stem.lineCapStyle = .round
stem.move(to: NSPoint(x: 372, y: 300)); stem.line(to: NSPoint(x: 372, y: 640)); stem.stroke()
let arc = NSBezierPath(); arc.lineWidth = stroke; arc.lineCapStyle = .round
arc.appendArc(withCenter: NSPoint(x: 540, y: 520), radius: 168, startAngle: 180, endAngle: 55, clockwise: false); arc.stroke()
// ponto do ".click"
brown.setFill(); NSBezierPath(ovalIn: NSRect(x: 676, y: 240, width: 128, height: 128)).fill()
dark.setFill(); NSBezierPath(ovalIn: NSRect(x: 712, y: 276, width: 56, height: 56)).fill()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
