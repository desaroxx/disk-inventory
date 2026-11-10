import AppKit
import DiskInventoryCore

/// Development aid for checking the UI without screen-recording access.
///
/// `DI_SNAPSHOT=/path/prefix` saves a PNG of every visible window once the first document is
/// ready. `DI_SCRIPT=step,step,…` then runs each step against that document and saves the
/// windows again after it, as `<prefix>-<n>-<step>-<window>.png`.
@MainActor
enum DebugSnapshot {
    static func startIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let prefix = env["DI_SNAPSHOT"] else { return }
        let steps = (env["DI_SCRIPT"] ?? "").split(separator: ",").map(String.init)
        Task {
            var document: DocumentModel?
            while document == nil {
                try? await Task.sleep(for: .milliseconds(250))
                document = AppState.shared.activeDocument.flatMap {
                    $0.state == .ready && $0.root != nil && $0.cleanupIsCurrent ? $0 : nil
                }
            }
            guard let document else { return }
            try? await Task.sleep(for: .seconds(1.5))
            snapshotAll(prefix: "\(prefix)-0-ready")
            for (index, step) in steps.enumerated() {
                run(step, on: document)
                try? await Task.sleep(for: .seconds(1.5))
                snapshotAll(prefix: "\(prefix)-\(index + 1)-\(step)")
            }
            log("script done")
            NSApp.terminate(nil)
        }
    }

    private static func run(_ step: String, on document: DocumentModel) {
        log("step \(step)")
        switch step {
        case "selectLargestFile":
            var node = document.root
            while let next = node.flatMap({ document.visibleChildren(of: $0).first }) { node = next }
            document.selection = node
        case "selectParent": document.selectParent()
        case "hoverSelection": document.hovered = document.selection
        case "zoomIn": document.zoomIn()
        case "zoomOut": document.zoomOut()
        case "kinds": document.showKindStatistics.toggle()
        case "list": document.showSelectionList.toggle()
        case "info": WindowManager.shared.toggleInfoPanel()
        case "packages": document.showPackageContents.toggle()
        case "logical": document.sizeMode = document.sizeMode == .physical ? .logical : .physical
        case "free": document.showFreeSpace.toggle()
        case "other": document.showOtherSpace.toggle()
        case "split": document.splitHorizontally.toggle()
        case "cleanup": document.showCleanup.toggle()
        case "tickSafe":
            document.checkedCleanup = Set(document.cleanupCandidates.filter { $0.rule.risk == .safe }.map(\.id))
            log("cleanup: \(document.cleanupCandidates.count) suggestions, \(document.checkedCleanup.count) ticked")
            for candidate in document.cleanupCandidates.prefix(15) {
                log("  \(candidate.rule.id) \(Format.bytes(candidate.node.physicalSize)) \(candidate.path)")
            }
        default: log("unknown step \(step)")
        }
    }

    private static func snapshotAll(prefix: String) {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            let name = window.title.isEmpty ? "untitled" : window.title.replacingOccurrences(of: "/", with: "_")
            save(window, to: "\(prefix)-\(index)-\(name).png")
        }
    }

    static func save(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        } catch {
            log("snapshot failed: \(error)")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("debug: \(message)\n".utf8))
    }
}
