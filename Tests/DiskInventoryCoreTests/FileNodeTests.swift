import Foundation
import Testing
@testable import DiskInventoryCore

@Suite struct FileNodeTests {
    /// root/{a/{x 10, y 20}, z 5}
    func tree() -> (root: FileNode, a: FileNode, x: FileNode) {
        let x = FileNode(name: "x", type: .file, kindName: "K", physicalSize: 10, logicalSize: 8)
        let y = FileNode(name: "y", type: .file, kindName: "K", physicalSize: 20, logicalSize: 19)
        let a = FileNode(name: "a", type: .directory, children: [x, y])
        let z = FileNode(name: "z", type: .file, kindName: "L", physicalSize: 5, logicalSize: 5)
        let root = FileNode(name: "root", type: .directory, children: [a, z], url: URL(filePath: "/tmp/root"))
        return (root, a, x)
    }

    @Test func removingANodeShrinksEveryAncestor() throws {
        let (root, _, x) = tree()
        let newRoot = try #require(FileNode.replacing(x, with: nil))
        #expect(newRoot.physicalSize == 25)
        #expect(newRoot.descendant(atNames: ["a"])?.physicalSize == 20)
        #expect(newRoot.descendant(atNames: ["a", "x"]) == nil)
        #expect(newRoot.url == root.url)
        #expect(root.physicalSize == 35, "the old tree's sizes are untouched")
    }

    @Test func replacingANodeUpdatesSizesAndParents() throws {
        // Parent links are weak; the document normally keeps the root alive.
        let (root, _, x) = tree()
        defer { withExtendedLifetime(root) {} }
        let bigger = FileNode(name: "x", type: .file, physicalSize: 100, logicalSize: 100)
        let newRoot = try #require(FileNode.replacing(x, with: bigger))
        #expect(newRoot.physicalSize == 125)
        #expect(newRoot.children.first?.name == "a", "children re-sorted by size")
        #expect(bigger.root === newRoot)
        #expect(bigger.url.path == "/tmp/root/a/x")
    }

    @Test func kindStatisticsTreatHiddenPackagesAsOneFile() {
        let inner = FileNode(name: "bin", type: .file, kindName: "Exec", physicalSize: 50)
        let app = FileNode(name: "T.app", type: .directory, kindName: "Application", isPackage: true, children: [inner])
        let doc = FileNode(name: "d.txt", type: .file, kindName: "Text", physicalSize: 7)
        let root = FileNode(name: "r", type: .directory, children: [app, doc])

        let hidden = KindStatistic.compute(for: root, showPackageContents: false, sizeMode: .physical)
        #expect(hidden.map(\.kindName) == ["Application", "Text"])
        #expect(hidden.first?.physicalSize == 50)

        let shown = KindStatistic.compute(for: root, showPackageContents: true, sizeMode: .physical)
        #expect(shown.map(\.kindName) == ["Exec", "Text"])
    }

    @Test func colorRegistryHandsOutTwelveColoursThenGrey() {
        let registry = KindColorRegistry()
        let kinds = (0..<15).map { "kind\($0)" }
        registry.assign(kinds)
        #expect(registry.color(forKind: "kind0") == KindColorRegistry.palette[0])
        #expect(registry.color(forKind: "kind11") == KindColorRegistry.palette[11])
        #expect(registry.color(forKind: "kind12") == KindColorRegistry.other)

        // Assignments are permanent: a later, larger kind does not steal a colour.
        registry.assign(["newcomer", "kind0"])
        #expect(registry.color(forKind: "newcomer") == KindColorRegistry.other)
        #expect(registry.color(forKind: "kind0") == KindColorRegistry.palette[0])
    }
}
