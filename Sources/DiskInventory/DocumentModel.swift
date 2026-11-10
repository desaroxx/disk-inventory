import AppKit
import DiskInventoryCore
import Observation

/// State of one scanned folder and its window.
@MainActor @Observable
final class DocumentModel: Identifiable {
    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    struct ZoomTransition: Equatable {
        let from: ObjectIdentifier
        let to: ObjectIdentifier
        let zoomingIn: Bool
    }

    let id = UUID()
    let url: URL
    let colors: KindColorRegistry
    private(set) var progress = ScanProgress()

    private(set) var state: LoadState = .loading
    private(set) var root: FileNode?
    private(set) var volume: VolumeInfo?
    /// Bumped whenever the tree is replaced (load, refresh, trash).
    private(set) var treeVersion = 0
    /// Bumped whenever new kinds receive colours.
    private(set) var colorsVersion = 0

    var selection: FileNode?
    /// The item under the mouse in the treemap.
    var hovered: FileNode?

    /// Folders zoomed into, outermost first. The treemap shows the last one (or the root).
    private(set) var zoomStack: [FileNode] = []
    private(set) var lastZoomTransition: ZoomTransition?

    var showPackageContents = Pref.bool(Pref.showPackageContents) { didSet { viewOptionsChanged() } }
    var sizeMode: SizeMode = Pref.bool(Pref.showPhysicalFileSize) ? .physical : .logical { didSet { viewOptionsChanged() } }
    var showFreeSpace = Pref.bool(Pref.showFreeSpace)
    var showOtherSpace = Pref.bool(Pref.showOtherSpace)
    var splitHorizontally = Pref.bool(Pref.splitWindowHorizontally)
    var showKindStatistics = false
    var showSelectionList = false
    /// Kind filter for the selection list; nil means all kinds.
    var selectionListKind: String?

    private(set) var kindStatistics: [KindStatistic] = []

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var logicalOrderCache: [ObjectIdentifier: [FileNode]] = [:]

    init(url: URL, colors: KindColorRegistry) {
        self.url = url
        self.colors = colors
    }

    var displayRoot: FileNode? { zoomStack.last ?? root }

    var title: String {
        guard let root else { return url.lastPathComponent }
        return "\(root.name) (\(Format.bytes(root.size(sizeMode))))"
    }

    // MARK: Loading

    func load() {
        state = .loading
        progress = ScanProgress()
        let url = url, progress = progress
        loadTask = Task {
            do {
                let (tree, volume) = try await Task.detached(priority: .userInitiated) {
                    (try await Scanner().scan(url, progress: progress), VolumeInfo(for: url))
                }.value
                self.volume = volume
                install(tree)
                state = .ready
            } catch is CancellationError {
            } catch {
                state = .failed("The folder's content could not be loaded.")
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
    }

    /// Swaps in a new tree, carrying selection and zoom over to the equivalent new nodes.
    private func install(_ newRoot: FileNode) {
        func remap(_ node: FileNode?) -> FileNode? {
            node.flatMap { newRoot.descendant(atNames: $0.namesFromRoot) }
        }
        let wasZoomed = zoomStack.map(\.namesFromRoot)
        root = newRoot
        selection = remap(selection)
        hovered = nil
        zoomStack = wasZoomed.compactMap { newRoot.descendant(atNames: $0) }
        lastZoomTransition = nil
        treeVersion += 1
        viewOptionsChanged()
    }

    private func viewOptionsChanged() {
        logicalOrderCache = [:]
        guard let root else { return }
        kindStatistics = KindStatistic.compute(for: root, showPackageContents: showPackageContents, sizeMode: sizeMode)
        colors.assign(kindStatistics.map(\.kindName))
        colorsVersion += 1
        if let kind = selectionListKind, !kindStatistics.contains(where: { $0.kindName == kind }) {
            selectionListKind = nil
        }
    }

    // MARK: Tree queries for the views

    /// Children as the files view shows them: none for hidden packages, sorted by the current size.
    func visibleChildren(of node: FileNode) -> [FileNode] {
        if node !== root, node.isLeaf(showPackageContents: showPackageContents) { return [] }
        guard sizeMode == .logical else { return node.children }
        if let cached = logicalOrderCache[node.id] { return cached }
        let sorted = node.children.sorted { $0.logicalSize > $1.logicalSize }
        logicalOrderCache[node.id] = sorted
        return sorted
    }

    /// Top-level treemap items: the zoomed folder plus optional free/other space tiles.
    var treemapItems: [FileNode] {
        guard let displayRoot else { return [] }
        guard displayRoot === root, let volume else { return [displayRoot] }
        var items = [displayRoot]
        if showFreeSpace, volume.availableCapacity > 0 {
            items.append(FileNode(name: "free space on drive", type: .other, kindName: "free space on drive",
                                  physicalSize: volume.availableCapacity, logicalSize: volume.availableCapacity,
                                  special: .freeSpace))
        }
        let other = volume.usedCapacity - displayRoot.physicalSize
        if showOtherSpace, canShowOtherSpace, other > 0 {
            items.append(FileNode(name: "space occupied by other files and folders", type: .other,
                                  kindName: "space occupied by other files and folders",
                                  physicalSize: other, logicalSize: other, special: .otherSpace))
        }
        return items
    }

    /// Other space only makes sense when a folder, not a whole drive, is shown.
    var canShowOtherSpace: Bool { volume.map { !$0.isVolumeRoot } ?? false }

    // MARK: Selection

    func selectParent() {
        guard let parent = selection?.parent else { return }
        selection = parent
    }

    var canSelectParent: Bool { selection?.parent != nil }

    // MARK: Zoom

    /// The folder Zoom In would show: the selected folder, or the folder containing the selected file.
    var zoomInTarget: FileNode? {
        guard let selection, let displayRoot, selection.special == nil else { return nil }
        var target: FileNode? = selection.isLeaf(showPackageContents: showPackageContents) ? selection.parent : selection
        if let candidate = target, candidate === displayRoot || displayRoot.path(to: candidate) == nil { target = nil }
        return target
    }

    func zoomIn() {
        guard let target = zoomInTarget, let from = displayRoot else { return }
        lastZoomTransition = ZoomTransition(from: from.id, to: target.id, zoomingIn: true)
        zoomStack.append(target)
    }

    var canZoomOut: Bool { !zoomStack.isEmpty }

    func zoomOut() {
        guard let from = zoomStack.popLast(), let to = displayRoot else { return }
        lastZoomTransition = ZoomTransition(from: from.id, to: to.id, zoomingIn: false)
    }

    /// Zooms out to `node`, which must be the root or on the zoom stack.
    func zoomOut(to node: FileNode) {
        guard let from = displayRoot, from !== node else { return }
        if node === root {
            zoomStack = []
        } else if let index = zoomStack.firstIndex(where: { $0 === node }) {
            zoomStack.removeSubrange((index + 1)...)
        } else {
            return
        }
        lastZoomTransition = ZoomTransition(from: from.id, to: node.id, zoomingIn: false)
    }

    /// Levels Zoom Out To can return to, innermost first.
    var zoomOutTargets: [FileNode] {
        guard let root, !zoomStack.isEmpty else { return [] }
        return ([root] + zoomStack.dropLast()).reversed()
    }

    // MARK: File actions

    func open(_ node: FileNode) {
        guard ensureExists(node) else { return }
        NSWorkspace.shared.open(node.url)
    }

    func open(_ node: FileNode, with app: URL) {
        guard ensureExists(node) else { return }
        NSWorkspace.shared.open([node.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func reveal(_ node: FileNode) {
        guard ensureExists(node) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    /// Rescans `node` (or the folder containing it) and splices the result into the tree.
    func refresh(_ node: FileNode) {
        guard state == .ready else { return }
        let target = node.isDirectory || node.parent == nil ? node : node.parent!
        let url = target.url
        Task {
            guard FileManager.default.fileExists(atPath: url.path) else {
                if let newRoot = FileNode.replacing(target, with: nil) { install(newRoot) }
                return
            }
            guard let fresh = try? await Task.detached(priority: .userInitiated, operation: {
                try await Scanner().scan(url)
            }).value else { return }
            // The tree may have been replaced while scanning (another refresh, trash).
            guard target.root === root else { return }
            // The scan names the node by its display name; keep the tree's own name.
            let renamed = FileNode(name: target.name, type: .directory, kindName: target.kindName,
                                   isPackage: target.isPackage, children: fresh.children)
            if let newRoot = FileNode.replacing(target, with: target.parent == nil ? fresh : renamed) {
                install(newRoot)
            }
        }
    }

    func refreshAll() {
        if let root { refresh(root) }
    }

    func moveToTrash(_ node: FileNode) {
        guard node.parent != nil, ensureExists(node) else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            alert("\"\(node.name)\" cannot be moved to the trash.",
                  info: "Maybe you do not have sufficient access privileges.")
            return
        }
        let parent = node.parent
        if let newRoot = FileNode.replacing(node, with: nil) {
            selection = parent
            install(newRoot)
        }
    }

    private func ensureExists(_ node: FileNode) -> Bool {
        if FileManager.default.fileExists(atPath: node.url.path) { return true }
        alert("\"\(node.name)\" does not exist any more.", info: nil)
        return false
    }

    private func alert(_ message: String, info: String?) {
        let alert = NSAlert()
        alert.messageText = message
        if let info { alert.informativeText = info }
        alert.runModal()
    }

    // MARK: Item actions (shared by every context menu)

    struct ItemAction {
        var title: String
        var isEnabled = true
        var perform: (() -> Void)?
        var submenu: [ItemAction]?
        var isSeparator = false

        init(title: String, isEnabled: Bool = true, submenu: [ItemAction]? = nil, isSeparator: Bool = false,
             perform: (() -> Void)? = nil) {
            self.title = title
            self.isEnabled = isEnabled
            self.submenu = submenu
            self.isSeparator = isSeparator
            self.perform = perform
        }

        static var separator: ItemAction { ItemAction(title: "", isSeparator: true) }
    }

    /// Context menu for `node` (spec §2): Open, Open With, Reveal, Refresh, Trash, Zoom.
    func actions(for node: FileNode) -> [ItemAction] {
        let isReal = node.special == nil
        var openWith: [ItemAction] = []
        if isReal {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: node.url)
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: node.url)
            func entry(_ app: URL, suffix: String = "") -> ItemAction {
                ItemAction(title: FileManager.default.displayName(atPath: app.path) + suffix) { [weak self] in
                    self?.open(node, with: app)
                }
            }
            if let defaultApp {
                openWith.append(entry(defaultApp, suffix: " (default)"))
                if apps.count > 1 { openWith.append(.separator) }
            }
            openWith += apps.filter { $0 != defaultApp }.map { entry($0) }
        }
        return [
            ItemAction(title: "Open", isEnabled: isReal) { [weak self] in self?.open(node) },
            ItemAction(title: "Open With", isEnabled: !openWith.isEmpty, submenu: openWith),
            .separator,
            ItemAction(title: "Reveal in Finder", isEnabled: isReal) { [weak self] in self?.reveal(node) },
            ItemAction(title: "Refresh", isEnabled: isReal) { [weak self] in self?.refresh(node) },
            .separator,
            ItemAction(title: "Move To Trash", isEnabled: isReal && node.parent != nil) { [weak self] in
                self?.moveToTrash(node)
            },
            .separator,
            ItemAction(title: "Zoom In", isEnabled: zoomInTarget != nil) { [weak self] in self?.zoomIn() },
            ItemAction(title: "Zoom Out", isEnabled: canZoomOut) { [weak self] in self?.zoomOut() },
        ]
    }
}
