import AppKit

@main
@MainActor
enum SimulTransEntry {
    // Strong reference to prevent deallocation (NSApplication.delegate is weak)
    static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
