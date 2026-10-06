import AppKit
import ImageIO

enum ItemKind: String, Codable {
    case screenshot, clipboardImage, clipboardText, ocr, ai, video
    var isImage: Bool { self == .screenshot || self == .clipboardImage }
    var isText: Bool { self == .clipboardText || self == .ocr || self == .ai }
}

struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var kind: ItemKind
    var text: String?
    var file: String?
    var source: String?
    var duration: Double?
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()
    static let maxItems = 500

    @Published private(set) var items: [Item] = []

    let dir: URL
    let imagesDir: URL
    let videosDir: URL
    private var indexURL: URL { dir.appendingPathComponent("history.json") }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("SnapLens", isDirectory: true)
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        videosDir = dir.appendingPathComponent("videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([Item].self, from: data) {
            items = decoded
        }
    }

    func url(for item: Item) -> URL? {
        item.file.map { (item.kind == .video ? videosDir : imagesDir).appendingPathComponent($0) }
    }

    @discardableResult
    func addImage(data: Data, kind: ItemKind, text: String? = nil) -> Item {
        let name = UUID().uuidString + ".png"
        try? data.write(to: imagesDir.appendingPathComponent(name))
        return insert(Item(kind: kind, text: text, file: name))
    }

    @discardableResult
    func addText(_ text: String, kind: ItemKind, source: String? = nil) -> Item {
        insert(Item(kind: kind, text: text, source: source))
    }

    @discardableResult
    func addVideo(file: String, duration: Double, source: String?) -> Item {
        insert(Item(kind: .video, file: file, source: source, duration: duration))
    }

    private func insert(_ item: Item) -> Item {
        items.insert(item, at: 0)
        // Vídeos ficam fora do limite: só o usuário os apaga.
        while items.filter({ $0.kind != .video }).count > Self.maxItems,
              let last = items.last(where: { $0.kind != .video }) {
            remove(last)
        }
        save()
        return item
    }

    func remove(_ item: Item) {
        if let u = url(for: item) { try? FileManager.default.removeItem(at: u) }
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear(where match: (ItemKind) -> Bool) {
        for item in items where match(item.kind) {
            if let u = url(for: item) { try? FileManager.default.removeItem(at: u) }
        }
        items.removeAll { match($0.kind) }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}

func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

func loadThumbnail(_ url: URL, maxSize: Int = 480) -> NSImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSize,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
