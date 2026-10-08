import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--stack"), i + 2 < args.count {
        // Teste da montagem: SnapLens --stack saida.png a.png b.png …
        let urls = args[(i + 2)...].map { URL(fileURLWithPath: $0) }
        if let d = Composer.stack(urls) { try? d.write(to: URL(fileURLWithPath: args[i + 1])); print("ok \(d.count) bytes") } else { print("falhou") }
        exit(0)
    }
    if let i = args.firstIndex(of: "--video-frames"), i + 1 < args.count {
        app.setActivationPolicy(.prohibited)
        Shots.renderVideoFrames(to: URL(fileURLWithPath: args[i + 1]), language: i + 2 < args.count ? args[i + 2] : nil)
        exit(0)
    }
    if let i = args.firstIndex(of: "--render-shots"), i + 1 < args.count {
        app.setActivationPolicy(.prohibited)
        Shots.render(to: URL(fileURLWithPath: args[i + 1]), language: i + 2 < args.count ? args[i + 2] : nil)
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
