import AppKit
import DiskInventoryCore
import SwiftUI

/// Selection List (spec §5): every file of one kind, filterable by a search field.
struct SelectionListView: View {
    let document: DocumentModel
    @AppStorage(Pref.useSmallFontInSelectionList) private var smallFont = false
    @State private var rows: [Row] = []
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var scope = Scope.all
    @State private var sortOrder = [KeyPathComparator(\Row.size, order: .reverse)]
    @State private var selectedRow: ObjectIdentifier?

    enum Scope: String, CaseIterable { case all = "All", name = "Name", kind = "Kind", path = "Path" }

    struct Row: Identifiable, Sendable {
        let node: FileNode
        let name: String
        let size: Int64
        let folder: String
        var id: ObjectIdentifier { node.id }
    }

    private struct Query: Equatable {
        var tree: Int
        var kind: String?
        var text: String
        var scope: Scope
        var showPackages: Bool
        var sizeMode: SizeMode
    }

    private var query: Query {
        Query(tree: document.treeVersion, kind: document.selectionListKind, text: searchText, scope: scope,
              showPackages: document.showPackageContents, sizeMode: document.sizeMode)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Show all files of kind:")
                Picker("", selection: Binding(get: { document.selectionListKind }, set: { document.selectionListKind = $0 })) {
                    Text("(all kinds)").tag(String?.none)
                    Divider()
                    ForEach(document.kindStatistics) { Text($0.kindName).tag(Optional($0.kindName)) }
                }
                .labelsHidden()
                .frame(width: 185)
                ProgressView().controlSize(.small).opacity(isSearching ? 1 : 0)
                Spacer()
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
                TextField("search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
            }
            .controlSize(.small)

            Table(rows, selection: $selectedRow, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { Text($0.name).lineLimit(1) }
                    .width(min: 40, ideal: 168)
                TableColumn("Size", value: \.size) { row in
                    Text(Format.bytes(row.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 10, ideal: 59)
                TableColumn("Path", value: \.folder) { Text($0.folder).lineLimit(1).truncationMode(.head) }
                    .width(min: 31, ideal: 150)
            }
            .font(smallFont ? .system(size: NSFont.smallSystemFontSize) : .body)
            .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    MenuBuilder.swiftUIItems(document.actions(for: row.node))
                }
            }
        }
        .padding(8)
        .onChange(of: sortOrder) { rows.sort(using: sortOrder) }
        .onChange(of: selectedRow) {
            if let id = selectedRow, let row = rows.first(where: { $0.id == id }) { document.selection = row.node }
        }
        .task(id: query) { await reload() }
    }

    private func reload() async {
        guard let root = document.root else { rows = []; return }
        isSearching = true
        defer { isSearching = false }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }

        let query = query, sortOrder = sortOrder
        let result = await Task.detached(priority: .userInitiated) {
            Self.matches(in: root, query: query).sorted(using: sortOrder)
        }.value
        guard !Task.isCancelled else { return }
        rows = result
    }

    nonisolated private static func matches(in root: FileNode, query: Query) -> [Row] {
        let needle = query.text.trimmingCharacters(in: .whitespaces)
        func matchesText(_ node: FileNode) -> Bool {
            guard !needle.isEmpty else { return true }
            func has(_ s: String) -> Bool { s.localizedCaseInsensitiveContains(needle) }
            switch query.scope {
            case .all: return has(node.name) || has(node.kindName) || has(node.folderPath)
            case .name: return has(node.name)
            case .kind: return has(node.kindName)
            case .path: return has(node.folderPath)
            }
        }
        var result: [Row] = []
        func visit(_ node: FileNode) {
            if node !== root, node.isLeaf(showPackageContents: query.showPackages) {
                if (query.kind == nil || node.kindName == query.kind), matchesText(node) {
                    result.append(Row(node: node, name: node.name, size: node.size(query.sizeMode), folder: node.folderPath))
                }
            } else {
                node.children.forEach(visit)
            }
        }
        visit(root)
        return result
    }
}
