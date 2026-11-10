import Darwin
import Foundation
import Synchronization

/// Live counters a UI can poll while a scan runs.
public final class ScanProgress: Sendable {
    private let files = Atomic<Int>(0)
    private let bytes = Atomic<Int64>(0)

    public init() {}

    public var fileCount: Int { files.load(ordering: .relaxed) }
    public var byteCount: Int64 { bytes.load(ordering: .relaxed) }

    func record(files n: Int, bytes b: Int64) {
        files.add(n, ordering: .relaxed)
        bytes.add(b, ordering: .relaxed)
    }
}

/// Hard links share one file ID; only the first name seen gets the bytes.
final class HardLinkRegistry: Sendable {
    private let seen = Mutex<Set<UInt64>>([])

    func isFirstSighting(_ fileID: UInt64) -> Bool {
        seen.withLock { $0.insert(fileID).inserted }
    }
}

public enum ScanError: Error {
    case cannotOpen(path: String, errno: Int32)
}

/// Walks a directory tree with `getattrlistbulk(2)`, one task per directory.
///
/// - Allocated size is counted, not logical size, so sparse files and compression are reflected.
/// - Hard-linked files are counted once.
/// - Symlinks are not followed, and other mounted volumes are skipped.
public struct Scanner: Sendable {
    public init() {}

    public func scan(_ url: URL, progress: ScanProgress = ScanProgress()) async throws -> FileNode {
        let seenLinks = HardLinkRegistry()
        let path = url.standardizedFileURL.path
        return try await scanDirectory(path: path, name: url.lastPathComponent,
                                       progress: progress, seenLinks: seenLinks, isRoot: true)
    }

    private func scanDirectory(path: String, name: String, progress: ScanProgress,
                               seenLinks: HardLinkRegistry, isRoot: Bool = false) async throws -> FileNode {
        try Task.checkCancellation()

        let entries: [Entry]
        do {
            entries = try Self.readEntries(path: path)
        } catch is ScanError where !isRoot {
            // Unreadable subdirectory (permissions, TCC): show it as empty rather than failing the scan.
            return FileNode(name: name, kind: .directory, size: 0)
        }

        var leaves: [FileNode] = []
        var subdirs: [Entry] = []
        var leafBytes: Int64 = 0

        for entry in entries {
            switch entry.kind {
            case .directory:
                if !entry.isMountPoint { subdirs.append(entry) }
            default:
                var size = entry.allocatedSize
                if entry.linkCount > 1 {
                    if !seenLinks.isFirstSighting(entry.fileID) { size = 0 }
                }
                leafBytes += size
                leaves.append(FileNode(name: entry.name, kind: entry.kind, size: size))
            }
        }
        progress.record(files: leaves.count, bytes: leafBytes)

        let dirs = try await withThrowingTaskGroup(of: FileNode.self) { group in
            for dir in subdirs {
                let childPath = path.hasSuffix("/") ? path + dir.name : path + "/" + dir.name
                group.addTask {
                    try await scanDirectory(path: childPath, name: dir.name, progress: progress, seenLinks: seenLinks)
                }
            }
            var result: [FileNode] = []
            for try await node in group { result.append(node) }
            return result
        }

        return FileNode(name: name, kind: .directory, size: 0, children: leaves + dirs)
    }

    // MARK: - getattrlistbulk

    /// The ATTR_* macros import as a mix of Int32 and UInt32.
    private static func bits(_ value: some BinaryInteger) -> attrgroup_t { attrgroup_t(truncatingIfNeeded: value) }

    struct Entry {
        var name: String
        var kind: FileNode.Kind
        var fileID: UInt64
        var linkCount: UInt32
        var allocatedSize: Int64
        var isMountPoint: Bool
    }

    static func readEntries(path: String) throws -> [Entry] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw ScanError.cannotOpen(path: path, errno: errno) }
        defer { close(fd) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = bits(ATTR_CMN_RETURNED_ATTRS)
            | bits(ATTR_CMN_NAME) | bits(ATTR_CMN_ERROR)
            | bits(ATTR_CMN_OBJTYPE) | bits(ATTR_CMN_FILEID)
        request.dirattr = bits(ATTR_DIR_MOUNTSTATUS)
        request.fileattr = bits(ATTR_FILE_LINKCOUNT) | bits(ATTR_FILE_ALLOCSIZE)

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

        if has(returned.commonattr, ATTR_CMN_ERROR) {
            let error = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            if error != 0 { return nil }
        }

        var name = ""
        if has(returned.commonattr, ATTR_CMN_NAME) {
            let ref = field.loadUnaligned(as: attrreference_t.self)
            name = String(cString: (field + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
            field += MemoryLayout<attrreference_t>.size
        }

        var objType: fsobj_type_t = 0
        if has(returned.commonattr, ATTR_CMN_OBJTYPE) {
            objType = field.loadUnaligned(as: fsobj_type_t.self)
            field += MemoryLayout<fsobj_type_t>.size
        }

        var fileID: UInt64 = 0
        if has(returned.commonattr, ATTR_CMN_FILEID) {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }

        var isMountPoint = false
        if has(returned.dirattr, ATTR_DIR_MOUNTSTATUS) {
            let status = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            isMountPoint = status & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
        }

        var linkCount: UInt32 = 1
        if has(returned.fileattr, ATTR_FILE_LINKCOUNT) {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }

        var allocatedSize: Int64 = 0
        if has(returned.fileattr, ATTR_FILE_ALLOCSIZE) {
            allocatedSize = field.loadUnaligned(as: off_t.self)
            field += MemoryLayout<off_t>.size
        }

        let kind: FileNode.Kind = switch vtype(rawValue: objType) {
        case VREG: .file
        case VDIR: .directory
        case VLNK: .symlink
        default: .other
        }

        return Entry(name: name, kind: kind, fileID: fileID, linkCount: linkCount,
                     allocatedSize: allocatedSize, isMountPoint: isMountPoint)
    }
}
