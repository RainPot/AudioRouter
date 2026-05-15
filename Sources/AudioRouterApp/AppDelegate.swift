import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var bootstrap: AppBootstrap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let bootstrap = AppBootstrap()
        bootstrap.start()
        self.bootstrap = bootstrap
    }

    func applicationWillTerminate(_ notification: Notification) {
        bootstrap?.stop()
    }
}
