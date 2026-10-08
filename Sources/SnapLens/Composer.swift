import AppKit

/// Monta várias imagens em uma só, empilhadas verticalmente com espaçamento de 1 cm.
enum Composer {
    /// 1 cm em pixels na densidade da tela principal (96 dpi lógicos × fator Retina).
    static var gapPixels: Int { Int((37.8 * (NSScreen.main?.backingScaleFactor ?? 2)).rounded()) }

    static func stack(_ urls: [URL]) -> Data? {
        let images = urls.compactMap { NSImage(contentsOf: $0) }.compactMap { img -> CGImage? in
            img.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard !images.isEmpty else { return nil }
        let gap = gapPixels
        let width = images.map(\.width).max() ?? 0
        let height = images.map(\.height).reduce(0, +) + gap * (images.count - 1)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CoreGraphics desenha de baixo para cima; a primeira imagem fica no topo.
        var y = height
        for img in images {
            y -= img.height
            ctx.draw(img, in: CGRect(x: 0, y: y, width: img.width, height: img.height))
            y -= gap
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}
