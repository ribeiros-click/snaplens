import Foundation
import Darwin

/// Vigia da thread principal: se ela ficar mais de `limit` segundos sem processar eventos,
/// registra no trace e encerra o app com abort(), o que gera um relatório em
/// ~/Library/Logs/DiagnosticReports com a pilha de todas as threads (onde travou).
enum HangWatchdog {
    nonisolated(unsafe) private static var lastPong = Date()
    private static let limit: TimeInterval = 20

    static func start() {
        let t = Thread {
            while true {
                DispatchQueue.main.async { lastPong = Date() }
                Thread.sleep(forTimeInterval: 2)
                let stalled = Date().timeIntervalSince(lastPong)
                if stalled > limit {
                    let msg = "HANG: thread principal sem responder há \(Int(stalled))s — encerrando para gerar relatório de diagnóstico\n"
                    // Escrita síncrona: o Trace normal usa uma fila que pode não esvaziar antes do abort.
                    if let h = try? FileHandle(forWritingTo: Trace.fileURL) {
                        h.seekToEndOfFile(); h.write(Data(msg.utf8)); try? h.close()
                    }
                    abort()
                }
            }
        }
        t.name = "snaplens.hang-watchdog"
        t.qualityOfService = .utility
        t.start()
    }
}
