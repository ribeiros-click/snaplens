import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let args = CommandLine.arguments
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
