import Foundation
import Testing
@testable import DiskInventoryCore

@Suite struct ScannerTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "DiskInventoryTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "a/b"), withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: root.appending(path: "big.bin"))
        try Data(count: 10).write(to: root.appending(path: "a/small.txt"))
        try Data(count: 50_000).write(to: root.appending(path: "a/b/mid.dat"))
        try fm.linkItem(at: root.appending(path: "big.bin"), to: root.appending(path: "a/hardlink.bin"))
        try fm.createSymbolicLink(at: root.appending(path: "loop"), withDestinationURL: root)
    }

    @Test func rollsUpSizesAndCountsHardLinksOnce() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await Scanner().scan(root)

        let big = try #require(tree.children.first { $0.name == "big.bin" })
        let a = try #require(tree.children.first { $0.name == "a" })
        #expect(big.size >= 100_000)
        #expect(tree.size == tree.children.reduce(0) { $0 + $1.size })
        #expect(a.size == a.children.reduce(0) { $0 + $1.size })

        // Exactly one of the two hard-linked names carries the bytes.
        let link = try #require(a.children.first { $0.name == "hardlink.bin" })
        #expect(big.size == 0 || link.size == 0)
        #expect(big.size + link.size >= 100_000)

        // big.bin, small.txt, mid.dat, hardlink.bin, loop
        #expect(tree.fileCount == 5)
    }

    @Test func doesNotFollowSymlinks() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await Scanner().scan(root)
        let loop = try #require(tree.children.first { $0.name == "loop" })
        #expect(loop.kind == .symlink)
        #expect(loop.children.isEmpty)
    }

    @Test func childrenAreSortedLargestFirst() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await Scanner().scan(root)
        let sizes = tree.children.map(\.size)
        #expect(sizes == sizes.sorted(by: >))
    }

    @Test func missingRootThrows() async {
        await #expect(throws: ScanError.self) {
            try await Scanner().scan(URL(filePath: "/nonexistent-\(UUID().uuidString)"))
        }
    }
}
