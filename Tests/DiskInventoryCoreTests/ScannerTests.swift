import Foundation
import Testing
@testable import DiskInventoryCore

@Suite struct ScannerTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "DiskInventoryTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "a/b"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Tool.app/Contents"), withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: root.appending(path: "big.bin"))
        try Data(count: 10).write(to: root.appending(path: "a/small.txt"))
        try Data(count: 50_000).write(to: root.appending(path: "a/b/mid.png"))
        try Data(count: 5_000).write(to: root.appending(path: "Tool.app/Contents/Info.plist"))
        try fm.linkItem(at: root.appending(path: "big.bin"), to: root.appending(path: "a/hardlink.bin"))
        try fm.createSymbolicLink(at: root.appending(path: "loop"), withDestinationURL: root)
    }

    private func scan() async throws -> FileNode {
        try await Scanner().scan(root)
    }

    @Test func rollsUpSizesAndCountsHardLinksOnce() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await scan()

        let big = try #require(tree.children.first { $0.name == "big.bin" })
        let a = try #require(tree.children.first { $0.name == "a" })
        #expect(big.physicalSize >= 100_000)
        #expect(tree.physicalSize == tree.children.reduce(0) { $0 + $1.physicalSize })
        #expect(a.logicalSize == a.children.reduce(0) { $0 + $1.logicalSize })

        // Exactly one of the two hard-linked names carries the bytes.
        let link = try #require(a.children.first { $0.name == "hardlink.bin" })
        #expect(big.logicalSize + link.logicalSize == 100_000)

        // big.bin, small.txt, mid.png, hardlink.bin, loop, Info.plist
        #expect(tree.fileCount == 6)
    }

    @Test func recordsLogicalAndPhysicalSizes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let small = try #require(try await scan().descendant(atNames: ["a", "small.txt"]))
        #expect(small.logicalSize == 10)
        #expect(small.physicalSize >= 10)
    }

    @Test func classifiesKindsAndPackages() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await scan()
        let app = try #require(tree.children.first { $0.name == "Tool.app" })
        #expect(app.isPackage)
        #expect(!(try #require(tree.children.first { $0.name == "a" })).isPackage)
        let png = try #require(tree.descendant(atNames: ["a", "b", "mid.png"]))
        #expect(png.kindName.localizedCaseInsensitiveContains("PNG"))
    }

    @Test func doesNotFollowSymlinks() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let loop = try #require(try await scan().children.first { $0.name == "loop" })
        #expect(loop.type == .symlink)
        #expect(loop.children.isEmpty)
    }

    @Test func nodesKnowTheirLocation() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = try await scan()
        let png = try #require(tree.descendant(atNames: ["a", "b", "mid.png"]))
        #expect(png.url.standardizedFileURL.path == root.appending(path: "a/b/mid.png").standardizedFileURL.path)
        #expect(png.folderPath == "\(tree.name)/a/b")
        #expect(tree.path(to: png)?.count == 4)
    }

    @Test func recordsModificationDates() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let past = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: root.appending(path: "a/small.txt").path)
        let tree = try await scan()
        let small = try #require(tree.descendant(atNames: ["a", "small.txt"]))
        #expect(small.modificationDate == past)
        let a = try #require(tree.children.first { $0.name == "a" })
        #expect(try #require(a.modificationDate) > past, "a folder carries its newest file's date")
    }

    @Test func missingRootThrows() async {
        await #expect(throws: ScanError.self) {
            try await Scanner().scan(URL(filePath: "/nonexistent-\(UUID().uuidString)"))
        }
    }
}
