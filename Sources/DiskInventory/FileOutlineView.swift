import AppKit
import DiskInventoryCore
import SwiftUI

/// NSOutlineView wrapper. SwiftUI's OutlineGroup becomes unusable with hundreds of thousands of rows;
/// NSOutlineView loads children lazily and recycles row views.
struct FileOutlineView: NSViewRepresentable {
    let root: FileNode
    @Binding var selection: FileNode?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.style = .fullWidth
        outline.allowsMultipleSelection = false

        for (id, title, width) in [("name", "Name", 220.0), ("size", "Size", 80.0), ("files", "Files", 70.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            if id != "name" { column.headerCell.alignment = .right }
            outline.addTableColumn(column)
            if id == "name" { outline.outlineTableColumn = column }
        }

        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        outline.reloadData()
        outline.expandItem(root)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let rootChanged = coordinator.parent.root !== root
        coordinator.parent = self
        guard let outline = coordinator.outline else { return }
        if rootChanged {
            outline.reloadData()
            outline.expandItem(root)
        }
        coordinator.reveal(selection)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: FileOutlineView
        weak var outline: NSOutlineView?
        private var isRevealing = false

        init(_ parent: FileOutlineView) { self.parent = parent }

        /// Expands ancestors of `node` and selects its row, so a click in the treemap shows up here.
        func reveal(_ node: FileNode?) {
            guard let outline else { return }
            guard let node else { outline.deselectAll(nil); return }
            if outline.item(atRow: outline.selectedRow) as? FileNode === node { return }
            guard let path = parent.root.path(to: node) else { return }

            isRevealing = true
            defer { isRevealing = false }
            for ancestor in path.dropLast() { outline.expandItem(ancestor) }
            let row = outline.row(forItem: node)
            if row >= 0 {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? FileNode else { return 1 }
            return node.children.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? FileNode else { return parent.root }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileNode).map { !$0.children.isEmpty } ?? false
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode, let column = tableColumn else { return nil }
            let id = column.identifier
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)

            switch id.rawValue {
            case "name":
                cell.textField?.stringValue = node.name
                cell.imageView?.image = NSImage(systemSymbolName: icon(for: node), accessibilityDescription: nil)
            case "size":
                cell.textField?.stringValue = Format.bytes(node.size)
            default:
                cell.textField?.stringValue = node.isDirectory ? Format.count(node.fileCount) : ""
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isRevealing, let outline else { return }
            let node = outline.item(atRow: outline.selectedRow) as? FileNode
            if parent.selection !== node { parent.selection = node }
        }

        private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text

            if id.rawValue == "name" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(image)
                cell.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                ])
            } else {
                text.alignment = .right
                text.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func icon(for node: FileNode) -> String {
            switch node.kind {
            case .directory: "folder"
            case .symlink: "arrow.up.right.square"
            case .file, .other: "doc"
            }
        }
    }
}
