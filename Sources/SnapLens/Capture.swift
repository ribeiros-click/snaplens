import AppKit
import ScreenCaptureKit

/// Captura de tela com ScreenCaptureKit (API nativa atual do macOS).
enum Capture {
    @MainActor
    static func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @MainActor
    static func screenImage(for screen: NSScreen) async -> CGImage? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let cfg = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        cfg.width = Int(screen.frame.width * scale)
        cfg.height = Int(screen.frame.height * scale)
        cfg.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }
}
