import Cocoa
import Foundation

// MARK: - App lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NanaMenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
    }
}

@main
struct NanaMenuMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
