import AppKit
import SwiftUI

/// Creates the loading, document and Information windows in AppKit, each hosting a SwiftUI view.
///
/// SwiftUI scenes can only be opened from inside a view, but folders also arrive as open-file
/// events (Dock drop, `open -a`, a path on the command line) that the app delegate handles.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var loadingWindows: [UUID: NSWindow] = [:]
    private var documentWindows: [UUID: NSWindow] = [:]
    private var infoPanel: NSPanel?

    /// Scans `url`, showing the loading panel until the document window opens.
    func open(_ url: URL) {
        guard let id = AppState.shared.startScan(url), let document = AppState.shared.document(id) else { return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: LoadingView(document: document)))
        window.title = "Loading folder contents..."
        window.styleMask = [.titled]
        window.isReleasedWhenClosed = false
        window.center()
        loadingWindows[id] = window
        window.makeKeyAndOrderFront(nil)
    }

    func loadingFinished(_ id: UUID) {
        loadingWindows.removeValue(forKey: id)?.close()
        guard let document = AppState.shared.document(id) else { return }
        guard document.state == .ready else {
            AppState.shared.close(id)
            return
        }
        let host = NSHostingController(rootView: MainWindowView(document: document))
        host.sceneBridgingOptions = [.toolbars]
        // Only the minimum size comes from SwiftUI; otherwise the window grows to every view's ideal size.
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 572, height: 521))
        window.contentMinSize = NSSize(width: 400, height: 300)
        window.setFrameAutosaveName("MainWindow")
        // Cascade from the previous document window instead of stacking exactly on top of it.
        if let last = documentWindows.values.first(where: \.isVisible) {
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        }
        documentWindows[id] = window
        // Menus act on the newest window even if the app is in the background and it never becomes key.
        AppState.shared.activeDocumentID = id
        window.makeKeyAndOrderFront(nil)
    }

    func cancelLoading(_ id: UUID) {
        AppState.shared.close(id)
        loadingWindows.removeValue(forKey: id)?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = documentWindows.first(where: { $0.value === window })?.key else { return }
        documentWindows[id] = nil
        AppState.shared.close(id)
    }

    // MARK: Information panel

    var isInfoPanelVisible: Bool { infoPanel?.isVisible ?? false }

    func toggleInfoPanel() {
        if let infoPanel, infoPanel.isVisible {
            infoPanel.orderOut(nil)
        } else {
            makeInfoPanel().orderFront(nil)
        }
        AppState.shared.isInfoPanelVisible = isInfoPanelVisible
    }

    private func makeInfoPanel() -> NSPanel {
        if let infoPanel { return infoPanel }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 300),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: true)
        panel.title = "Information"
        panel.contentViewController = NSHostingController(rootView: InfoPanelView())
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("InfoPanel")
        if let screen = NSScreen.main?.visibleFrame, panel.frame.origin == .zero {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 280, y: screen.maxY - 20))
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated { AppState.shared.isInfoPanelVisible = false }
        }
        infoPanel = panel
        return panel
    }

}
