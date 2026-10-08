import Vision
import AppKit

/// OCR com o framework Vision (modelo de ML nativo, roda 100% no dispositivo).
enum OCR {
    static func recognize(url: URL) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            let handler = VNImageRequestHandler(url: url, options: [:])
            do { try handler.perform([request]) } catch { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}

extension OCR {
    /// Descrição sem provedor externo: etiquetas do Vision + texto reconhecido.
    static func nativeDescription(url: URL) async -> String {
        let labels: [String] = await Task.detached(priority: .userInitiated) {
            let req = VNClassifyImageRequest()
            guard (try? VNImageRequestHandler(url: url, options: [:]).perform([req])) != nil else { return [] }
            return (req.results ?? []).filter { $0.confidence > 0.2 }.prefix(6)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
        let text = await recognize(url: url).trimmingCharacters(in: .whitespacesAndNewlines)
        var out = L("Descrição nativa (sem IA externa — configure um provedor em Ajustes para descrições completas)")
        if !labels.isEmpty { out += "\n" + L("Elementos detectados: ") + labels.joined(separator: ", ") }
        if !text.isEmpty { out += "\n\n" + L("Texto na imagem:") + "\n" + text }
        return out
    }
}
