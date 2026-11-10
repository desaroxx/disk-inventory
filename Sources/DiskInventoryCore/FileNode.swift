import Foundation

public enum SizeMode: Sendable {
    /// Space allocated on disk.
    case physical
    /// Length of the file's content.
    case logical
}

/// One entry in the scanned tree.
///
/// Nodes are immutable apart from the `parent` back-pointer, which a parent sets on its
/// children when it is created. Edits (refresh, move to trash) build new ancestors with
/// `replacing(_:with:)` instead of mutating, so a tree being drawn is never changed underneath.
public final class FileNode: @unchecked Sendable, Identifiable {
    public enum NodeType: Sendable { case file, directory, symlink, other }

    /// Synthetic treemap tiles that stand for space outside the scanned tree.
    public enum Special: Sendable { case freeSpace, otherSpace }

    public let name: String
    public let type: NodeType
    /// Finder-style kind, e.g. "Application" or "PNG image". Empty for plain folders.
    public let kindName: String
    /// A directory the Finder shows as a single file (.app, .bundle, .photoslibrary…).
    public let isPackage: Bool
    public let physicalSize: Int64
    public let logicalSize: Int64
    /// Number of non-directory entries beneath this node (1 for a file).
    public let fileCount: Int
    /// Sorted by physical size, largest first.
    public let children: [FileNode]
    public let special: Special?
    /// Absolute location; only stored on a tree's root.
    private let rootURL: URL?

    public private(set) weak var parent: FileNode?

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public var isDirectory: Bool { type == .directory }

    public init(name: String, type: NodeType, kindName: String = "", isPackage: Bool = false,
                physicalSize: Int64 = 0, logicalSize: Int64 = 0, children: [FileNode] = [],
                special: Special? = nil, url: URL? = nil) {
        self.name = name
        self.type = type
        self.kindName = kindName
        self.isPackage = isPackage
        self.special = special
        self.rootURL = url
        if type == .directory {
            self.children = children.sorted { $0.physicalSize > $1.physicalSize }
            self.physicalSize = physicalSize + children.reduce(0) { $0 + $1.physicalSize }
            self.logicalSize = logicalSize + children.reduce(0) { $0 + $1.logicalSize }
            self.fileCount = children.reduce(0) { $0 + $1.fileCount }
        } else {
            self.children = []
            self.physicalSize = physicalSize
            self.logicalSize = logicalSize
            self.fileCount = special == nil ? 1 : 0
        }
        for child in self.children { child.parent = self }
    }

    public func size(_ mode: SizeMode) -> Int64 {
        mode == .physical ? physicalSize : logicalSize
    }

    /// Whether this node is drawn as a single tile / shown without a disclosure triangle.
    public func isLeaf(showPackageContents: Bool) -> Bool {
        !isDirectory || (isPackage && !showPackageContents)
    }

    public var url: URL {
        if let parent { return parent.url.appending(path: name, directoryHint: isDirectory ? .isDirectory : .notDirectory) }
        return rootURL ?? URL(filePath: "/")
    }

    /// From the tree's root down to `self`, inclusive.
    public var ancestry: [FileNode] {
        var chain: [FileNode] = []
        var node: FileNode? = self
        while let current = node { chain.append(current); node = current.parent }
        return chain.reversed()
    }

    public var root: FileNode { ancestry[0] }

    /// Names from the root's name to the folder containing this node, joined with "/".
    public var folderPath: String {
        ancestry.dropLast().map(\.name).joined(separator: "/")
    }

    /// Nodes from `self` down to `target`, inclusive. Nil if `target` is not in this subtree.
    public func path(to target: FileNode) -> [FileNode]? {
        let chain = target.ancestry
        guard let start = chain.firstIndex(where: { $0 === self }) else { return nil }
        return Array(chain[start...])
    }

    /// Follows child names from this node.
    public func descendant(atNames names: some Sequence<String>) -> FileNode? {
        var node = self
        for name in names {
            guard let next = node.children.first(where: { $0.name == name }) else { return nil }
            node = next
        }
        return node
    }

    /// Child names from the tree's root down to this node.
    public var namesFromRoot: [String] { ancestry.dropFirst().map(\.name) }

    /// Returns a new root in which `old` is replaced by `new` (or removed when `new` is nil).
    /// Ancestors of `old` are rebuilt so their sizes stay correct; untouched subtrees are shared.
    public static func replacing(_ old: FileNode, with new: FileNode?) -> FileNode? {
        var current = old
        var replacement = new
        while let parent = current.parent {
            var kids = parent.children.filter { $0 !== current }
            if let replacement { kids.append(replacement) }
            replacement = parent.copy(children: kids)
            current = parent
        }
        if current === old, let new, new.rootURL == nil {
            // Replacing the root itself: keep its location.
            return new.copy(children: new.children, url: old.url)
        }
        return replacement
    }

    func copy(children: [FileNode], url: URL? = nil) -> FileNode {
        FileNode(name: name, type: type, kindName: kindName, isPackage: isPackage,
                 children: children, special: special, url: url ?? rootURL)
    }
}
