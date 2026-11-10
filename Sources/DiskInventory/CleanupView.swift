import AppKit
import DiskInventoryCore
import SwiftUI

/// Cleanup suggestions: what the rules found, ticked items highlighted in the treemap,
/// and one button that moves the ticked ones to the Trash after asking.
struct CleanupView: View {
    let document: DocumentModel
    @State private var sortOrder = [KeyPathComparator(\Row.size, order: .reverse)]
    @State private var selectedRow: String?

    struct Row: Identifiable {
        let candidate: CleanupCandidate
        var id: String { candidate.id }
        var name: String { candidate.node.name }
        var size: Int64 { candidate.node.physicalSize }
        var ruleTitle: String { candidate.rule.title }
        var risk: Int { candidate.rule.risk == .safe ? 0 : 1 }
        var path: String { candidate.path }
        /// The folder holding the item, relative to the scanned folder, so the many
        /// same-named items (`node_modules`, `.build`) can be told apart.
        let folder: String
    }

    private var rows: [Row] {
        let rootPath = document.root?.url.path(percentEncoded: false) ?? ""
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return document.cleanupCandidates.map { candidate in
            let parent = (candidate.path as NSString).deletingLastPathComponent
            let relative = parent.hasPrefix(prefix) ? String(parent.dropFirst(prefix.count)) : parent
            return Row(candidate: candidate, folder: relative.isEmpty ? "—" : relative)
        }
        .sorted(using: sortOrder)
    }

    var body: some View {
        let candidates = document.cleanupCandidates
        let checked = document.checkedCandidates
        VStack(alignment: .leading, spacing: 6) {
            Text(summary(candidates)).foregroundStyle(.secondary).lineLimit(1).controlSize(.small)
            HStack(spacing: 8) {
                Button("Tick Safe") {
                    document.checkedCleanup.formUnion(candidates.filter { $0.rule.risk == .safe }.map(\.id))
                }
                .disabled(candidates.allSatisfy { $0.rule.risk != .safe || document.checkedCleanup.contains($0.id) })
                Button("Untick All") { document.checkedCleanup = [] }
                    .disabled(checked.isEmpty)
                Button(checked.isEmpty ? "Move to Trash…" : "Move \(Format.bytes(total(checked))) to Trash…") {
                    document.trashCheckedCleanup()
                }
                .disabled(checked.isEmpty)
            }
            .controlSize(.small)

            Table(rows, selection: $selectedRow, sortOrder: $sortOrder) {
                TableColumn("") { row in
                    Toggle("", isOn: Binding(get: { document.checkedCleanup.contains(row.id) },
                                             set: { on in
                                                 if on { document.checkedCleanup.insert(row.id) }
                                                 else { document.checkedCleanup.remove(row.id) }
                                             }))
                        .labelsHidden()
                }
                .width(20)
                TableColumn("Item", value: \.path) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).lineLimit(1)
                        Text(row.folder).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                    }
                    .help(row.path)
                }
                .width(min: 100, ideal: 220)
                TableColumn("Size", value: \.size) { row in
                    Text(Format.bytes(row.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 40, ideal: 70)
                TableColumn("Risk", value: \.risk) { row in RiskBadge(risk: row.candidate.rule.risk) }
                    .width(min: 50, ideal: 90)
                TableColumn("Why", value: \.ruleTitle) { row in
                    Text(row.ruleTitle).lineLimit(1).help(row.candidate.rule.explanation)
                }
                .width(min: 60, ideal: 150)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
                    MenuBuilder.swiftUIItems(document.actions(for: row.candidate.node))
                }
            }
            .overlay {
                if candidates.isEmpty {
                    Text("No suggestions in this folder.").foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .onChange(of: selectedRow) {
            if let id = selectedRow, let candidate = candidates.first(where: { $0.id == id }) {
                document.selection = candidate.node
            }
        }
    }

    private func total(_ candidates: [CleanupCandidate]) -> Int64 {
        candidates.reduce(0) { $0 + $1.node.physicalSize }
    }

    private func summary(_ candidates: [CleanupCandidate]) -> String {
        guard !candidates.isEmpty else { return "Cleanup suggestions" }
        let safe = candidates.filter { $0.rule.risk == .safe }
        return "\(candidates.count) suggestions, \(Format.bytes(total(candidates))) · \(Format.bytes(total(safe))) rebuilds itself"
    }
}

private struct RiskBadge: View {
    let risk: CleanupRisk

    var body: some View {
        let (title, color): (String, Color) = risk == .safe ? ("Safe", .green) : ("Check first", .orange)
        Text(title)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}
