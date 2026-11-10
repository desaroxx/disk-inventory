import AppKit
import SwiftUI

@main
struct DiskInventoryApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        Pref.registerDefaults()
    }

    var body: some Scene {
        // Shown at launch. Document, loading and Information windows are AppKit windows
        // managed by WindowManager, so open-file events can create them too.
        Window("Volumes", id: "volumes") {
            VolumesView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 532, height: 263)
        .commands { AppCommands() }

        Settings {
            PreferencesView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` launches a bare executable with no bundle; without this it gets no Dock icon or key focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        DebugSnapshot.startIfRequested()
        // `DiskInventory -open <folder>`: AppKit reads `-key value` arguments as user defaults.
        // (A bare path argument is swallowed as an open-file request by an unbundled executable.)
        if let path = UserDefaults.standard.string(forKey: "open") {
            WindowManager.shared.open(URL(filePath: (path as NSString).expandingTildeInPath))
        }
    }

    /// Folders dropped on the Dock icon, opened with `open -a`, or passed on the command line.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(WindowManager.shared.open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
