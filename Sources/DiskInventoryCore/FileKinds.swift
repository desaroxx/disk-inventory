import Foundation
import Synchronization
import UniformTypeIdentifiers

/// Maps a file to its Finder-style kind name. Lookups are per extension and cached,
/// so classifying a million files costs one Launch Services query per distinct extension.
public final class KindClassifier: Sendable {
    public static let shared = KindClassifier()

    private let cache = Mutex<[String: (kind: String, isPackage: Bool)]>([:])

    public let folderKind = UTType.folder.localizedDescription ?? "Folder"
    public let documentKind = UTType.data.localizedDescription ?? "Document"
    public let executableKind = UTType.unixExecutable.localizedDescription ?? "Unix Executable File"
    public let symlinkKind = UTType.symbolicLink.localizedDescription ?? "Alias"

    public func classify(name: String, type: FileNode.NodeType, isExecutable: Bool) -> (kind: String, isPackage: Bool) {
        let ext = Self.pathExtension(of: name)
        switch type {
        case .symlink:
            return (symlinkKind, false)
        case .directory:
            guard !ext.isEmpty else { return (folderKind, false) }
            let info = lookup(ext, directory: true)
            return info.isPackage ? info : (folderKind, false)
        case .file, .other:
            if ext.isEmpty { return (isExecutable ? executableKind : documentKind, false) }
            return (lookup(ext, directory: false).kind, false)
        }
    }

    private func lookup(_ ext: String, directory: Bool) -> (kind: String, isPackage: Bool) {
        let key = directory ? "/" + ext : ext
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let result: (kind: String, isPackage: Bool)
        // Folder extensions (.app, .bundle) only resolve when the lookup is scoped to directories.
        if let type = UTType(filenameExtension: ext, conformingTo: directory ? .directory : .data), !type.isDynamic {
            result = (type.localizedDescription ?? documentKind, type.conforms(to: .package))
        } else {
            result = (directory ? folderKind : documentKind, false)
        }
        cache.withLock { $0[key] = result }
        return result
    }

    static func pathExtension(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

public struct KindStatistic: Identifiable, Sendable, Hashable {
    public let kindName: String
    public var physicalSize: Int64
    public var logicalSize: Int64
    public var fileCount: Int

    public var id: String { kindName }
    public func size(_ mode: SizeMode) -> Int64 { mode == .physical ? physicalSize : logicalSize }

    /// Totals per kind over every leaf under `root`, largest first.
    public static func compute(for root: FileNode, showPackageContents: Bool, sizeMode: SizeMode) -> [KindStatistic] {
        var byKind: [String: KindStatistic] = [:]
        func visit(_ node: FileNode) {
            if node !== root, node.isLeaf(showPackageContents: showPackageContents) {
                byKind[node.kindName, default: KindStatistic(kindName: node.kindName, physicalSize: 0,
                                                             logicalSize: 0, fileCount: 0)]
                    .add(node)
            } else {
                node.children.forEach(visit)
            }
        }
        visit(root)
        return byKind.values.sorted { $0.size(sizeMode) > $1.size(sizeMode) }
    }

    private mutating func add(_ node: FileNode) {
        physicalSize += node.physicalSize
        logicalSize += node.logicalSize
        fileCount += 1
    }
}

public struct RGB: Sendable, Hashable {
    public var r, g, b: Float
    public init(_ r: Float, _ g: Float, _ b: Float) { self.r = r; self.g = g; self.b = b }
}

/// Hands out 12 colours to the largest kinds, first come first served; everything else is grey.
/// Assignments never change once made, so one registry can be shared by every window.
public final class KindColorRegistry: Sendable {
    public static let palette: [RGB] = [
        RGB(0.25, 0.25, 1.00), RGB(1.00, 0.25, 0.25), RGB(0.25, 0.95, 0.25),
        RGB(0.15, 0.90, 0.90), RGB(0.95, 0.15, 0.95), RGB(0.95, 0.95, 0.15),
        RGB(0.50, 0.50, 0.90), RGB(0.90, 0.50, 0.50), RGB(0.50, 0.85, 0.50),
        RGB(0.40, 0.80, 0.80), RGB(0.85, 0.45, 0.85), RGB(0.80, 0.80, 0.40),
    ]
    public static let other = RGB(0.62, 0.62, 0.62)
    public static let freeSpace = RGB(0.96, 0.96, 0.96)
    public static let otherSpace = RGB(0.30, 0.30, 0.30)

    private let assigned = Mutex<[String: Int]>([:])

    public init() {}

    /// Assigns free colours to `kinds` in order (callers pass them largest first).
    public func assign(_ kinds: [String]) {
        assigned.withLock { map in
            for kind in kinds where map[kind] == nil {
                guard map.count < Self.palette.count else { return }
                map[kind] = map.count
            }
        }
    }

    public func color(forKind kind: String) -> RGB {
        assigned.withLock { $0[kind] }.map { Self.palette[$0] } ?? Self.other
    }

    public func color(for node: FileNode) -> RGB {
        switch node.special {
        case .freeSpace: Self.freeSpace
        case .otherSpace: Self.otherSpace
        case nil: color(forKind: node.kindName)
        }
    }

    public var snapshot: [String: RGB] {
        assigned.withLock { $0.mapValues { Self.palette[$0] } }
    }
}
