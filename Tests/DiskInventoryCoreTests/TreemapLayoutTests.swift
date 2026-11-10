import CoreGraphics
import Testing
@testable import DiskInventoryCore

@Suite struct TreemapLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    @Test func tileAreasAreProportionalToSize() {
        let sizes: [Int64] = [6000, 6000, 4000, 3000, 2000, 2000, 1000]
        let root = FileNode(name: "root", kind: .directory, size: 0,
                            children: sizes.enumerated().map { FileNode(name: "f\($0)", kind: .file, size: $1) })
        let tiles = TreemapLayout.layout(root, in: bounds)

        #expect(tiles.count == sizes.count)
        let total = Double(bounds.width * bounds.height)
        for tile in tiles {
            let expected = Double(tile.node.size) / Double(root.size) * total
            #expect(abs(Double(tile.rect.width * tile.rect.height) - expected) < 0.01)
        }
    }

    @Test func tilesStayInBoundsAndDoNotOverlap() {
        let root = FileNode(name: "root", kind: .directory, size: 0, children: [
            FileNode(name: "d", kind: .directory, size: 0, children: (1...40).map {
                FileNode(name: "n\($0)", kind: .file, size: Int64($0 * 37 % 101 + 1))
            }),
            FileNode(name: "x", kind: .file, size: 900),
        ])
        let tiles = TreemapLayout.layout(root, in: bounds)
        let slack = bounds.insetBy(dx: -0.001, dy: -0.001)

        for tile in tiles { #expect(slack.contains(tile.rect)) }
        for i in tiles.indices {
            for j in tiles.indices where j > i {
                let overlap = tiles[i].rect.intersection(tiles[j].rect)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.001)
            }
        }
    }

    @Test func squarifyKeepsAspectRatiosReasonable() {
        let rects = TreemapLayout.squarify([6, 6, 4, 3, 2, 2, 1].map { $0 * 1000.0 },
                                           in: CGRect(x: 0, y: 0, width: 150, height: 160))
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 3)
    }

    @Test func emptyAndZeroSizedNodesProduceNoTiles() {
        let root = FileNode(name: "root", kind: .directory, size: 0, children: [
            FileNode(name: "empty", kind: .directory, size: 0),
            FileNode(name: "zero", kind: .file, size: 0),
        ])
        #expect(TreemapLayout.layout(root, in: bounds).isEmpty)
    }
}
