import Foundation
import os

/// Trace de diagnóstico: grava em ~/Library/Logs/SnapLens/snaplens.log (e no unified log do macOS).
/// Barato o suficiente para ficar ligado durante o desenvolvimento.
enum Trace {
    private static let logger = Logger(subsystem: "com.jjunior.snaplens", category: "trace")
    private static let queue = DispatchQueue(label: "snaplens.trace")
    private static let maxBytes = 2 * 1024 * 1024
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"; return f
    }()

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SnapLens", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snaplens.log")
    }()

    static func log(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
        let msg = message()
        let thread = Thread.isMainThread ? "main" : "bg"
        let src = (file as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
        let text = "\(formatter.string(from: Date())) [\(thread)] \(src):\(line) \(msg)\n"
        logger.info("\(src):\(line) \(msg, privacy: .public)")
        queue.async {
            rotateIfNeeded()
            if let h = try? FileHandle(forWritingTo: fileURL) {
                h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
            } else {
                try? text.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Últimas `lines` linhas do log (para "Copiar diagnóstico").
    static func tail(_ lines: Int = 200) -> String {
        guard let s = try? String(contentsOf: fileURL, encoding: .utf8) else { return "(log vazio)" }
        return s.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }

    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > maxBytes else { return }
        let old = fileURL.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }
}
