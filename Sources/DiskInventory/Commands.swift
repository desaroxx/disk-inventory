import AppKit
import DiskInventoryCore
import SwiftUI

/// Menu bar (spec §7). Commands act on the most recently key document window.
struct AppCommands: Commands {
    private var state: AppState { AppState.shared }
    private var document: DocumentModel? { state.activeDocument }
    private var ready: DocumentModel? { document?.state == .ready ? document : nil }
    private var selection: FileNode? { ready?.selection.flatMap { $0.special == nil ? $0 : nil } }

    var body: some Commands {
        // File
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { state.chooseFolder().map(open) }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(state.recentFolders, id: \.self) { url in
                    Button(FileManager.default.displayName(atPath: url.path)) { open(url) }
                }
                Divider()
                Button("Clear Menu") { state.clearRecentFolders() }
                    .disabled(state.recentFolders.isEmpty)
            }
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {
            Button("Reveal in Finder") { selection.map { ready?.reveal($0) } }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(selection == nil)
            Button("Refresh Selection") { selection.map { ready?.refresh($0) } }
                .disabled(selection == nil)
            Button("Refresh All") { ready?.refreshAll() }
                .disabled(ready == nil)
            Divider()
            Button("Move To Trash") { selection.map { ready?.moveToTrash($0) } }
                .keyboardShortcut(.delete)
                .disabled(selection?.parent == nil)
        }

        // View
        CommandGroup(before: .toolbar) {
            Button("Zoom In") { ready?.zoomIn() }
                .keyboardShortcut("+")
                .disabled(ready?.zoomInTarget == nil)
            Button("Zoom Out") { ready?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(!(ready?.canZoomOut ?? false))
            Menu("Zoom Out To") {
                ForEach(ready?.zoomOutTargets ?? []) { node in
                    Button(node.name) { ready?.zoomOut(to: node) }
                }
            }
            .disabled(ready?.zoomOutTargets.isEmpty ?? true)
            Divider()
            Button("Select Parent Folder") { ready?.selectParent() }
                .keyboardShortcut("u")
                .disabled(!(ready?.canSelectParent ?? false))
            Divider()
            toggle(ready?.showFreeSpace, show: "Show Free Space", hide: "Hide Free Space") {
                $0.showFreeSpace.toggle()
            }
            toggle(ready?.showOtherSpace, show: "Show Other Space", hide: "Hide Other Space") {
                $0.showOtherSpace.toggle()
            }
            .disabled(!(ready?.canShowOtherSpace ?? false))
            Divider()
            toggle(ready?.showPackageContents, show: "Show Package Contents", hide: "Hide Package Contents") {
                $0.showPackageContents.toggle()
            }
            toggle(ready.map { $0.sizeMode == .physical }, show: "Show Physical File Size", hide: "Show Logical File Size") {
                $0.sizeMode = $0.sizeMode == .physical ? .logical : .physical
            }
            Divider()
            Button(ready?.splitHorizontally == true ? "Split Vertically" : "Split Horizontally") {
                ready?.splitHorizontally.toggle()
            }
            .disabled(ready == nil)
            Divider()
        }

        // Window
        CommandGroup(before: .windowArrangement) {
            toggle(ready?.showKindStatistics, show: "Show File Kind Statistics", hide: "Hide File Kind Statistics") {
                $0.showKindStatistics.toggle()
            }
            toggle(ready?.showSelectionList, show: "Show Selection List", hide: "Hide Selection List") {
                $0.showSelectionList.toggle()
            }
            toggle(ready?.showCleanup, show: "Show Cleanup Suggestions", hide: "Hide Cleanup Suggestions") {
                $0.showCleanup.toggle()
            }
            Divider()
            Button(state.isInfoPanelVisible ? "Hide Information" : "Show Information") { InfoPanel.toggle() }
                .keyboardShortcut("i")
            Divider()
        }

        CommandGroup(replacing: .help) {}
        ToolbarCommands()
    }

    private func open(_ url: URL) {
        WindowManager.shared.open(url)
    }

    /// A menu item whose title flips between "Show …" and "Hide …" with the current state.
    private func toggle(_ isOn: Bool?, show: String, hide: String,
                        _ change: @escaping (DocumentModel) -> Void) -> some View {
        Button(isOn == true ? hide : show) { ready.map(change) }
            .disabled(isOn == nil)
    }
}
