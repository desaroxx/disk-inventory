import AppKit
import DiskInventoryCore
import SwiftUI

/// A document window (spec §2): files view and treemap side by side, two status lines,
/// the kind statistics on the right and the selection list along the bottom.
struct MainWindowView: View {
    let document: DocumentModel
    @AppStorage(Pref.useSmallFontInFilesView) private var smallFilesFont = false

    var body: some View {
        VStack(spacing: 0) {
            split
            StatusLines(document: document)
            if document.showSelectionList {
                Divider()
                SelectionListView(document: document)
                    .frame(height: 167)
            }
        }
        .inspector(isPresented: Binding(get: { document.showKindStatistics },
                                        set: { document.showKindStatistics = $0 })) {
            KindStatisticsView(document: document)
                .inspectorColumnWidth(min: 300, ideal: 390, max: 600)
        }
        .navigationTitle(document.title)
        .toolbar(id: "MainWindowToolbar") { MainToolbar(document: document) }
        .background(WindowKeyObserver(documentID: document.id, title: document.title))
    }

    @ViewBuilder private var split: some View {
        let files = FileOutlineView(document: document, treeVersion: document.treeVersion, selection: document.selection,
                                    showPackageContents: document.showPackageContents, sizeMode: document.sizeMode,
                                    smallFont: smallFilesFont)
            .frame(minWidth: 150, minHeight: 100)
        let treemap = TreemapView(
            document: document,
            inputs: TreemapInputs(treeVersion: document.treeVersion, colorsVersion: document.colorsVersion,
                                  displayRoot: document.displayRoot?.id, sizeMode: document.sizeMode,
                                  showPackageContents: document.showPackageContents,
                                  showFreeSpace: document.showFreeSpace, showOtherSpace: document.showOtherSpace),
            selection: document.selection, transition: document.lastZoomTransition)
            .frame(minWidth: 150, minHeight: 100)

        if document.splitHorizontally {
            VSplitView { files; treemap }
        } else {
            HSplitView { files; treemap }
        }
    }
}

/// The two lines under the split view: the item under the mouse (or the selection).
private struct StatusLines: View {
    let document: DocumentModel

    var body: some View {
        let node = document.hovered ?? document.selection
        VStack(alignment: .leading, spacing: 2) {
            Text(node.map(nameLine) ?? " ").lineLimit(1).truncationMode(.middle)
            Text(node.map(kindLine) ?? " ").font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 17)
        .padding(.vertical, 6)
    }

    private func nameLine(_ node: FileNode) -> String {
        node.special != nil || node.parent == nil ? node.name : "\(node.name) (\(node.folderPath))"
    }

    private func kindLine(_ node: FileNode) -> String {
        let kind = node.isDirectory && !node.isPackage ? KindClassifier.shared.folderKind : node.kindName
        return "\(kind), \(Format.bytes(node.size(document.sizeMode)))"
    }
}

/// Toolbar (spec §2): Zoom In, Zoom Out, flexible space, File Kind Statistics by default.
private struct MainToolbar: CustomizableToolbarContent {
    let document: DocumentModel

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "ZoomIn") {
            Button("Zoom In", systemImage: "plus.magnifyingglass") { document.zoomIn() }
                .disabled(document.zoomInTarget == nil)
        }
        ToolbarItem(id: "ZoomOut") {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { document.zoomOut() }
                .disabled(!document.canZoomOut)
        }
        ToolbarItem(id: "ShowInfo", showsByDefault: false) {
            Button("Show Information", systemImage: "info.circle") { InfoPanel.toggle() }
        }
        ToolbarItem(id: "ShowPackageContents", showsByDefault: false) {
            Toggle(isOn: Binding(get: { document.showPackageContents }, set: { document.showPackageContents = $0 })) {
                Label("Show Package Contents",
                      systemImage: document.showPackageContents ? "shippingbox.and.arrow.backward" : "shippingbox")
            }
        }
        ToolbarItem(id: "RevealInFinder", showsByDefault: false) {
            Button("Reveal in Finder", systemImage: "finder") { document.selection.map(document.reveal) }
                .disabled(document.selection?.special != nil || document.selection == nil)
        }
        ToolbarItem(id: "RefreshSelection", showsByDefault: false) {
            Button("Refresh Selection", systemImage: "arrow.clockwise") { document.selection.map(document.refresh) }
                .disabled(document.selection == nil)
        }
        ToolbarItem(id: "RefreshAll", showsByDefault: false) {
            Button("Refresh All", systemImage: "arrow.triangle.2.circlepath") { document.refreshAll() }
        }
        ToolbarItem(id: "MoveToTrash", showsByDefault: false) {
            Button("Move to Trash", systemImage: "trash") { document.selection.map(document.moveToTrash) }
                .disabled(document.selection?.parent == nil)
        }
        ToolbarItem(id: "flexible") { Spacer() }
        ToolbarItem(id: "ToggleKindsStatisticDrawer") {
            Toggle(isOn: Binding(get: { document.showKindStatistics }, set: { document.showKindStatistics = $0 })) {
                Label("File Kind Statistics", systemImage: "chart.bar.doc.horizontal")
            }
            .help(document.showKindStatistics ? "Hide File Kind Statistics" : "Show File Kind Statistics")
        }
    }
}

/// Tells AppState which document window is key, so menus and the Information panel follow it.
private struct WindowKeyObserver: NSViewRepresentable {
    let documentID: UUID
    /// AppKit-hosted windows don't pick up `navigationTitle`, so the title is set here.
    let title: String

    func makeNSView(context: Context) -> Observer { Observer(documentID: documentID) }
    func updateNSView(_ observer: Observer, context: Context) {
        observer.title = title
    }

    final class Observer: NSView {
        let documentID: UUID
        private var token: NSObjectProtocol?
        var title = "" {
            didSet { applyTitle() }
        }

        /// The window mirrors its content view controller's title, so that is what gets set.
        private func applyTitle() {
            guard let window else { return }
            if let controller = window.contentViewController { controller.title = title } else { window.title = title }
        }

        init(documentID: UUID) {
            self.documentID = documentID
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            token.map(NotificationCenter.default.removeObserver)
            guard let window else { return }
            applyTitle()
            if window.isKeyWindow { AppState.shared.activeDocumentID = documentID }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                           queue: .main) { [documentID] _ in
                MainActor.assumeIsolated { AppState.shared.activeDocumentID = documentID }
            }
        }
    }
}

/// Shown while a folder is scanned (spec §1); opens the document window when done.
struct LoadingView: View {
    let document: DocumentModel
    @State private var path = ""
    @State private var fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loading \(path)")
                .lineLimit(3)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .topLeading)
            if let fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Spacer()
                Button("Cancel") { WindowManager.shared.cancelLoading(document.id) }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 408)
        .task {
            // A whole volume has a known total, so its progress can be shown as a fraction.
            let volume = VolumeInfo(for: document.url).flatMap { $0.isVolumeRoot && $0.usedCapacity > 0 ? $0 : nil }
            while document.state == .loading {
                path = document.progress.currentPath
                if let volume {
                    fraction = min(1, Double(document.progress.byteCount) / Double(volume.usedCapacity))
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if case .failed(let message) = document.state {
                let alert = NSAlert()
                alert.messageText = message
                alert.informativeText = document.url.path
                alert.runModal()
            }
            WindowManager.shared.loadingFinished(document.id)
        }
    }
}

/// Launch panel listing mounted volumes (spec §1).
struct VolumesView: View {
    @State private var volumes: [Volume] = []
    @State private var selected: URL?

    struct Volume: Identifiable {
        let url: URL
        let name: String
        let icon: NSImage
        let total: Int64
        let free: Int64
        var id: URL { url }
        var used: Int64 { total - free }
    }

    var body: some View {
        VStack(spacing: 16) {
            Table(volumes, selection: $selected) {
                TableColumn("") { volume in
                    Image(nsImage: volume.icon).resizable().frame(width: 40, height: 40)
                }
                .width(50)
                TableColumn("Volume") { volume in
                    Text(volume.name).font(.headline)
                }
                .width(min: 100, ideal: 147)
                TableColumn("Usage") { volume in
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: Double(volume.used), total: Double(max(volume.total, 1)))
                        Text("\(Format.bytes(volume.used)) of \(Format.bytes(volume.total)) used")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tableStyle(.bordered)
            .environment(\.defaultMinListRowHeight, 45)
            .contextMenu(forSelectionType: URL.self) { _ in } primaryAction: { urls in
                urls.first.map(open)
            }

            HStack {
                GroupBox {
                    HStack {
                        Text("Select Folder:")
                        Button("…") { AppState.shared.chooseFolder().map(open) }
                    }
                    .padding(.horizontal, 4)
                }
                Spacer()
                Button("Open Volume") { selected.map(open) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 532, minHeight: 263)
        .onAppear(perform: reload)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in reload() }
    }

    private func open(_ url: URL) {
        WindowManager.shared.open(url)
    }

    private func reload() {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let total = values.volumeTotalCapacity else { return nil }
            return Volume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent,
                          icon: NSWorkspace.shared.icon(forFile: url.path), total: Int64(total),
                          free: VolumeInfo(for: url)?.availableCapacity ?? Int64(values.volumeAvailableCapacity ?? 0))
        }
    }
}
