import Darwin
import Foundation
import Synchronization

/// Live counters a UI can poll while a scan runs.
public final class ScanProgress: Sendable {
    private let files = Atomic<Int>(0)
    private let bytes = Atomic<Int64>(0)
    private let lastPath = Mutex<String>("")

    public init() {}

    public var fileCount: Int { files.load(ordering: .relaxed) }
    public var byteCount: Int64 { bytes.load(ordering: .relaxed) }
    /// The directory most recently entered.
    public var currentPath: String { lastPath.withLock { $0 } }

    func record(files n: Int, bytes b: Int64) {
        files.add(n, ordering: .relaxed)
        bytes.add(b, ordering: .relaxed)
    }

    func entered(_ path: String) {
        lastPath.withLock { $0 = path }
    }
}

public enum ScanError: Error {
    case cannotOpen(path: String, errno: Int32)
}

/// Hard links share one file ID; only the first name seen gets the bytes.
final class HardLinkRegistry: Sendable {
    private let seen = Mutex<Set<UInt64>>([])

    func isFirstSighting(_ fileID: UInt64) -> Bool {
        seen.withLock { $0.insert(fileID).inserted }
    }
}

/// Walks a directory tree with `getattrlistbulk(2)`, one task per directory.
///
/// - Records both allocated (physical) and content (logical) size.
/// - Hard-linked files are counted once.
/// - Symlinks are not followed, and other mounted volumes are skipped.
public struct Scanner: Sendable {
    private let classifier: KindClassifier

    public init(classifier: KindClassifier = .shared) {
        self.classifier = classifier
    }

    public func scan(_ url: URL, progress: ScanProgress = ScanProgress()) async throws -> FileNode {
        let url = url.standardizedFileURL
        let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
        let (kind, isPackage) = classifier.classify(name: url.lastPathComponent, type: .directory, isExecutable: false)
        let node = try await scanDirectory(path: url.path, name: name, kind: kind, isPackage: isPackage,
                                           progress: progress, seenLinks: HardLinkRegistry(), isRoot: true)
        return node.copy(children: node.children, url: url)
    }

    private func scanDirectory(path: String, name: String, kind: String, isPackage: Bool, progress: ScanProgress,
                               seenLinks: HardLinkRegistry, isRoot: Bool = false) async throws -> FileNode {
        try Task.checkCancellation()
        progress.entered(path)

        let entries: [Entry]
        do {
            entries = try Self.readEntries(path: path)
        } catch is ScanError where !isRoot {
            // Unreadable subdirectory (permissions, privacy protection): show it as empty.
            return FileNode(name: name, type: .directory, kindName: kind, isPackage: isPackage)
        }

        var leaves: [FileNode] = []
        var subdirs: [Entry] = []
        var leafBytes: Int64 = 0

        for entry in entries {
            if entry.type == .directory {
                if !entry.isMountPoint { subdirs.append(entry) }
                continue
            }
            var physical = entry.allocatedSize
            var logical = entry.logicalSize
            if entry.linkCount > 1, !seenLinks.isFirstSighting(entry.fileID) {
                physical = 0
                logical = 0
            }
            leafBytes += physical
            let (kind, _) = classifier.classify(name: entry.name, type: entry.type, isExecutable: entry.isExecutable)
            leaves.append(FileNode(name: entry.name, type: entry.type, kindName: kind,
                                   physicalSize: physical, logicalSize: logical, modificationDate: entry.modificationDate))
        }
        progress.record(files: leaves.count, bytes: leafBytes)

        let dirs = try await withThrowingTaskGroup(of: FileNode.self) { group in
            for dir in subdirs {
                let childPath = path.hasSuffix("/") ? path + dir.name : path + "/" + dir.name
                let (kind, isPackage) = classifier.classify(name: dir.name, type: .directory, isExecutable: false)
                group.addTask {
                    try await scanDirectory(path: childPath, name: dir.name, kind: kind, isPackage: isPackage,
                                            progress: progress, seenLinks: seenLinks)
                }
            }
            var result: [FileNode] = []
            for try await node in group { result.append(node) }
            return result
        }

        return FileNode(name: name, type: .directory, kindName: kind, isPackage: isPackage, children: leaves + dirs)
    }

    // MARK: - getattrlistbulk

    /// The ATTR_* macros import as a mix of Int32 and UInt32.
    private static func bits(_ value: some BinaryInteger) -> attrgroup_t { attrgroup_t(truncatingIfNeeded: value) }

    struct Entry {
        var name: String
        var type: FileNode.NodeType
        var fileID: UInt64
        var isExecutable: Bool
        var linkCount: UInt32
        var logicalSize: Int64
        var allocatedSize: Int64
        var isMountPoint: Bool
        var modificationDate: Date?
    }

    static func readEntries(path: String) throws -> [Entry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ScanError.cannotOpen(path: path, errno: errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = bits(ATTR_CMN_RETURNED_ATTRS)
            | bits(ATTR_CMN_NAME) | bits(ATTR_CMN_ERROR) | bits(ATTR_CMN_OBJTYPE)
            | bits(ATTR_CMN_MODTIME) | bits(ATTR_CMN_ACCESSMASK) | bits(ATTR_CMN_FILEID)
        request.dirattr = bits(ATTR_DIR_MOUNTSTATUS)
        request.fileattr = bits(ATTR_FILE_LINKCOUNT) | bits(ATTR_FILE_TOTALSIZE) | bits(ATTR_FILE_ALLOCSIZE)

        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var entries: [Entry] = []
        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 {
                if errno == EINTR { continue }
                throw ScanError.cannotOpen(path: path, errno: errno)
            }
            if count == 0 { break }

            var cursor = buffer
            for _ in 0..<count {
                let length = Int(cursor.loadUnaligned(as: UInt32.self))
                if let entry = parseEntry(at: cursor) { entries.append(entry) }
                cursor += length
            }
        }
        return entries
    }

    /// Fields come back in this order: length, returned set, error, then the remaining
    /// attributes in bit order within groups ordered common, dir, file. See getattrlistbulk(2).
    private static func parseEntry(at start: UnsafeMutableRawPointer) -> Entry? {
        var field = start + MemoryLayout<UInt32>.size
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        func has(_ group: attrgroup_t, _ bit: some BinaryInteger) -> Bool { group & bits(bit) != 0 }
        func read<T>(_: T.Type) -> T {
            defer { field += MemoryLayout<T>.size }
            return field.loadUnaligned(as: T.self)
        }

        if has(returned.commonattr, ATTR_CMN_ERROR), read(UInt32.self) != 0 { return nil }

        var name = ""
        if has(returned.commonattr, ATTR_CMN_NAME) {
            let ref = field.loadUnaligned(as: attrreference_t.self)
            name = String(cString: (field + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
            field += MemoryLayout<attrreference_t>.size
        }

        let objType = has(returned.commonattr, ATTR_CMN_OBJTYPE) ? read(fsobj_type_t.self) : 0
        let modified = has(returned.commonattr, ATTR_CMN_MODTIME) ? read(timespec.self) : nil
        let mode = has(returned.commonattr, ATTR_CMN_ACCESSMASK) ? read(UInt32.self) : 0
        let fileID = has(returned.commonattr, ATTR_CMN_FILEID) ? read(UInt64.self) : 0
        let mountStatus = has(returned.dirattr, ATTR_DIR_MOUNTSTATUS) ? read(UInt32.self) : 0
        let linkCount = has(returned.fileattr, ATTR_FILE_LINKCOUNT) ? read(UInt32.self) : 1
        let logical = has(returned.fileattr, ATTR_FILE_TOTALSIZE) ? read(off_t.self) : 0
        let allocated = has(returned.fileattr, ATTR_FILE_ALLOCSIZE) ? read(off_t.self) : 0

        let type: FileNode.NodeType = switch vtype(rawValue: objType) {
        case VREG: .file
        case VDIR: .directory
        case VLNK: .symlink
        default: .other
        }

        return Entry(name: name, type: type, fileID: fileID, isExecutable: mode & 0o111 != 0,
                     linkCount: linkCount, logicalSize: logical, allocatedSize: allocated,
                     isMountPoint: mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0,
                     modificationDate: modified.map { Date(timeIntervalSince1970: TimeInterval($0.tv_sec) + TimeInterval($0.tv_nsec) / 1e9) })
    }
}

/// Capacity of the volume holding a scanned folder, for the free/other space tiles.
public struct VolumeInfo: Sendable {
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    /// The scanned folder is the volume's root.
    public let isVolumeRoot: Bool

    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }

    public init?(for url: URL) {
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity else { return nil }
        totalCapacity = Int64(total)
        availableCapacity = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        isVolumeRoot = values.volume?.standardizedFileURL.path == url.standardizedFileURL.path
    }
}
