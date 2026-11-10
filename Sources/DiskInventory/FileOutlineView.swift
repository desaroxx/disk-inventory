import AppKit
import DiskInventoryCore
import SwiftUI

/// The files view (spec §2): an outline with Name and Size columns, children largest first.
/// NSOutlineView rather than SwiftUI because it loads rows lazily and copes with millions of items.
struct FileOutlineView: NSViewRepresentable {
    let document: DocumentModel
    // Passed explicitly so SwiftUI calls updateNSView when they change.
    let treeVersion: Int
    let selection: FileNode?
    let showPackageContents: Bool
    let sizeMode: SizeMode
    let smallFont: Bool

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = ClippingOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.style = .fullWidth
        outline.allowsMultipleSelection = false
        outline.autosaveName = "FilesView"
        outline.autosaveTableColumns = true
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let name = NSTableColumn(identifier: .init("displayName"))
        name.title = "Name"
        name.width = 181
        name.minWidth = 16
        let size = NSTableColumn(identifier: .init("size"))
        size.title = "Size"
        size.width = 72
        size.minWidth = 40
        size.headerCell.alignment = .right
        outline.addTableColumn(name)
        outline.addTableColumn(size)
        outline.outlineTableColumn = name

        let coordinator = context.coordinator
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.menu = NSMenu()
        outline.menu?.delegate = coordinator
        coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        let document: DocumentModel
        weak var outline: NSOutlineView?
        private var shown: (tree: Int, packages: Bool, mode: SizeMode, small: Bool)?
        private var isRevealing = false

        init(document: DocumentModel) { self.document = document }

        func update(_ view: FileOutlineView) {
            guard let outline else { return }
            let next = (view.treeVersion, view.showPackageContents, view.sizeMode, view.smallFont)
            if shown.map({ $0 != next }) ?? true {
                let expanded = expandedPaths()
                outline.rowHeight = view.smallFont ? 14 : 17
                outline.reloadData()
                if let root = document.root {
                    outline.expandItem(root)
                    for names in expanded {
                        root.descendant(atNames: names).map { outline.expandItem($0) }
                    }
                }
                shown = next
            }
            reveal(view.selection)
        }

        private func expandedPaths() -> [[String]] {
            guard let outline else { return [] }
            return (0..<outline.numberOfRows).compactMap { row in
                guard let node = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(node) else { return nil }
                return node.namesFromRoot
            }
        }

        /// Expands ancestors of `node` and selects its row, so a click in the treemap shows up here.
        func reveal(_ node: FileNode?) {
            guard let outline else { return }
            isRevealing = true
            defer { isRevealing = false }
            guard let node, let root = document.root, let path = root.path(to: node) else {
                outline.deselectAll(nil)
                return
            }
            if outline.item(atRow: outline.selectedRow) as? FileNode === node { return }
            // A node inside a hidden package has no row; select the package instead.
            let visible = path.firstIndex { $0 !== root && $0.isLeaf(showPackageContents: document.showPackageContents) }
                .map { path[$0] } ?? node
            for ancestor in path where ancestor !== visible { outline.expandItem(ancestor) }
            let row = outline.row(forItem: visible)
            if row >= 0 {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? FileNode else { return document.root == nil ? 0 : 1 }
            return document.visibleChildren(of: node).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? FileNode else { return document.root! }
            return document.visibleChildren(of: node)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode).map { !document.visibleChildren(of: $0).isEmpty } ?? false
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode, let column = tableColumn else { return nil }
            let id = column.identifier
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
            let fontSize = outlineView.rowHeight < 17 ? NSFont.smallSystemFontSize : NSFont.systemFontSize
            cell.textField?.font = id.rawValue == "size"
                ? .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular) : .systemFont(ofSize: fontSize)

            if id.rawValue == "displayName" {
                cell.textField?.stringValue = node.name
                let icon = NSWorkspace.shared.icon(forFile: node.url.path)
                icon.size = NSSize(width: 16, height: 16)
                cell.imageView?.image = icon
            } else {
                cell.textField?.stringValue = Format.bytes(node.size(document.sizeMode))
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRevealing, let outline else { return }
            let node = outline.item(atRow: outline.selectedRow) as? FileNode
            if document.selection !== node { document.selection = node }
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outline, outline.clickedRow >= 0,
                  let node = outline.item(atRow: outline.clickedRow) as? FileNode else { return }
            document.selection = node
            for item in MenuBuilder.nsMenu(document.actions(for: node)).items {
                item.menu?.removeItem(item)
                menu.addItem(item)
            }
        }

        private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            cell.clipsToBounds = true
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text

            if id.rawValue == "displayName" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                ])
            } else {
                text.alignment = .right
                text.lineBreakMode = .byClipping
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }
}

/// Deep rows are indented past the Name column's width, and NSOutlineView then lets their cell
/// run into the Size column. Keep every cell inside its own column.
final class ClippingOutlineView: NSOutlineView {
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        let frame = super.frameOfCell(atColumn: column, row: row)
        guard column >= 0, column < numberOfColumns else { return frame }
        let columnRect = rect(ofColumn: column)
        let minX = min(frame.minX, columnRect.maxX)
        return NSRect(x: minX, y: frame.minY, width: max(0, min(frame.maxX, columnRect.maxX) - minX), height: frame.height)
    }
}
