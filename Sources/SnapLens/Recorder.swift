import AppKit
import AVFoundation
import ScreenCaptureKit

/// Gravação de tela com ScreenCaptureKit (macOS 15+): vídeo H.264 em .mp4,
/// com áudio do sistema e/ou microfone opcionais.
@MainActor
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    static let shared = Recorder()
    static let stateChanged = Notification.Name("SnapLensRecordingChanged")

    private(set) var isRecording = false
    private(set) var startDate: Date?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var fileName = ""
    private var sourceLabel = ""
    private var finishing = false
    private var finishFallback: Task<Void, Never>?

    enum Failure: LocalizedError {
        case noPermission, noMic
        var errorDescription: String? {
            switch self {
            case .noPermission: return "Permita “Gravação de Tela” ao SnapLens em Ajustes e tente de novo"
            case .noMic: return "Permita o Microfone ao SnapLens em Ajustes ou desative o microfone"
            }
        }
    }

    static var systemAudio: Bool {
        get { UserDefaults.standard.object(forKey: "rec.system") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "rec.system") }
    }
    static var microphone: Bool {
        get { UserDefaults.standard.bool(forKey: "rec.mic") }
        set { UserDefaults.standard.set(newValue, forKey: "rec.mic") }
    }

    func start(screen: NSScreen) async throws {
        guard !isRecording else { return }
        let wantSystem = Self.systemAudio, wantMic = Self.microphone

        if wantMic {
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.noMic }
        }
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == id }) else { throw Failure.noPermission }

        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        cfg.width = Int(screen.frame.width * scale)
        cfg.height = Int(screen.frame.height * scale)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.showsCursor = true
        cfg.capturesAudio = wantSystem
        cfg.excludesCurrentProcessAudio = true
        cfg.captureMicrophone = wantMic

        let name = UUID().uuidString + ".mp4"
        let url = Store.shared.videosDir.appendingPathComponent(name)
        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = url
        rc.outputFileType = .mp4
        rc.videoCodecType = .h264

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        let out = SCRecordingOutput(configuration: rc, delegate: self)
        try s.addRecordingOutput(out)
        try await s.startCapture()

        stream = s
        recordingOutput = out
        fileName = name
        sourceLabel = [wantSystem ? "áudio do sistema" : nil, wantMic ? "microfone" : nil]
            .compactMap { $0 }.joined(separator: " + ").nonEmpty ?? "sem áudio"
        startDate = Date()
        isRecording = true
        finishing = false
        NotificationCenter.default.post(name: Self.stateChanged, object: nil)
    }

    /// Para a gravação; o item entra no histórico quando o arquivo termina de ser escrito.
    func stop() async {
        guard isRecording, let s = stream else { return }
        isRecording = false
        finishing = true
        NotificationCenter.default.post(name: Self.stateChanged, object: nil)
        try? await s.stopCapture()
        // Se o delegate não avisar, finaliza mesmo assim.
        finishFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await self?.finalize()
        }
    }

    private func finalize() async {
        guard finishing else { return }
        finishing = false
        finishFallback?.cancel()
        stream = nil
        recordingOutput = nil
        let url = Store.shared.videosDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Toast.show("A gravação falhou: arquivo não foi criado", symbol: "exclamationmark.triangle.fill")
            return
        }
        let seconds = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? Date().timeIntervalSince(startDate ?? Date())
        Store.shared.addVideo(file: fileName, duration: seconds.isFinite ? seconds : 0, source: sourceLabel)
        NSSound(named: "Glass")?.play()
        Toast.show("Gravação salva na biblioteca (\(formatDuration(seconds)))", symbol: "video.fill")
        NotificationCenter.default.post(name: Self.stateChanged, object: nil)
    }

    // MARK: SCRecordingOutputDelegate / SCStreamDelegate

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in await self.finalize() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            Toast.show("Erro na gravação: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
            if self.isRecording { await self.stop() }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.isRecording else { return }
            self.isRecording = false
            self.finishing = true
            NotificationCenter.default.post(name: Self.stateChanged, object: nil)
            await self.finalize()
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

func formatDuration(_ t: Double) -> String {
    let s = Int(t.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}

func loadVideoThumbnail(_ url: URL) async -> NSImage? {
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: 480, height: 480)
    guard let cg = try? await gen.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
