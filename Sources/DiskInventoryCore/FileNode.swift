import Foundation

/// One entry in the scanned tree. Immutable once built, so it can be shared across threads.
public final class FileNode: Sendable, Identifiable {
    public enum Kind: Sendable { case file, directory, symlink, other }

    public let name: String
    public let kind: Kind
    /// Bytes allocated on disk. For a directory, the sum of everything beneath it.
    public let size: Int64
    /// Number of files beneath this node (1 for a file).
    public let fileCount: Int
    /// Sorted largest first.
    public let children: [FileNode]

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public var isDirectory: Bool { kind == .directory }

    public var fileExtension: String {
        guard kind == .file, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    public init(name: String, kind: Kind, size: Int64, children: [FileNode] = []) {
        self.name = name
        self.kind = kind
        if kind == .directory {
            self.children = children.sorted { $0.size > $1.size }
            self.size = size + children.reduce(0) { $0 + $1.size }
            self.fileCount = children.reduce(0) { $0 + $1.fileCount }
        } else {
            self.children = []
            self.size = size
            self.fileCount = 1
        }
    }

    /// Nodes from `self` down to `target`, inclusive. Nil if `target` is not in this subtree.
    public func path(to target: FileNode) -> [FileNode]? {
        if self === target { return [self] }
        for child in children where child.isDirectory || child === target {
            if let rest = child.path(to: target) { return [self] + rest }
        }
        return nil
    }
}
