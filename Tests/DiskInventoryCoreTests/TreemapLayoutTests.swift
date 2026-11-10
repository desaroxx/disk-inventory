import CoreGraphics
import Foundation
import Testing
@testable import DiskInventoryCore

@Suite struct TreemapLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    func files(_ sizes: [Int64]) -> [FileNode] {
        sizes.enumerated().map { FileNode(name: "f\($0)", type: .file, physicalSize: $1, logicalSize: $1 / 2) }
    }

    @Test func tileAreasAreProportionalToSize() {
        let root = FileNode(name: "root", type: .directory, children: files([6000, 6000, 4000, 3000, 2000, 2000, 1000]))
        let result = TreemapLayout.layout(root, in: bounds)

        #expect(result.tiles.count == 7)
        let total = Double(bounds.width * bounds.height)
        for tile in result.tiles {
            let expected = Double(tile.node.physicalSize) / Double(root.physicalSize) * total
            #expect(abs(Double(tile.rect.width * tile.rect.height) - expected) < 0.01)
        }
    }

    @Test func tilesStayInBoundsAndDoNotOverlap() {
        let root = FileNode(name: "root", type: .directory, children: [
            FileNode(name: "d", type: .directory, children: files((1...40).map { Int64($0 * 37 % 101 + 1) })),
            FileNode(name: "x", type: .file, physicalSize: 900),
        ])
        let tiles = TreemapLayout.layout(root, in: bounds).tiles
        let slack = bounds.insetBy(dx: -0.001, dy: -0.001)

        for tile in tiles { #expect(slack.contains(tile.rect)) }
        for i in tiles.indices {
            for j in tiles.indices where j > i {
                let overlap = tiles[i].rect.intersection(tiles[j].rect)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.001)
            }
        }
    }

    @Test func foldersGetRectsButNoTiles() throws {
        let d = FileNode(name: "d", type: .directory, children: files([10, 20]))
        let root = FileNode(name: "root", type: .directory, children: [d] + files([30]))
        let result = TreemapLayout.layout(root, in: bounds)
        #expect(result.tiles.count == 3)
        let rect = try #require(result.rect(for: d))
        #expect(abs(rect.width * rect.height - bounds.width * bounds.height / 2) < 0.01)
    }

    @Test func hiddenPackagesAreSingleTiles() {
        let app = FileNode(name: "A.app", type: .directory, isPackage: true, children: files([10, 20, 30]))
        let root = FileNode(name: "root", type: .directory, children: [app])
        #expect(TreemapLayout.layout(root, in: bounds, options: .init(showPackageContents: false)).tiles.count == 1)
        #expect(TreemapLayout.layout(root, in: bounds, options: .init(showPackageContents: true)).tiles.count == 3)
    }

    @Test func logicalModeUsesLogicalSizes() throws {
        let root = FileNode(name: "root", type: .directory, children: [
            FileNode(name: "sparse", type: .file, physicalSize: 10, logicalSize: 1000),
            FileNode(name: "dense", type: .file, physicalSize: 1000, logicalSize: 1000),
        ])
        let result = TreemapLayout.layout(root, in: bounds, options: .init(sizeMode: .logical))
        let sparse = try #require(result.tiles.first { $0.node.name == "sparse" })
        #expect(abs(sparse.rect.width * sparse.rect.height - bounds.width * bounds.height / 2) < 0.01)
    }

    @Test func extraTopLevelItemsShareTheCanvas() {
        let root = FileNode(name: "root", type: .directory, children: files([300]))
        let free = FileNode(name: "free", type: .other, physicalSize: 100, logicalSize: 100, special: .freeSpace)
        let tiles = TreemapLayout.layout([root, free], in: bounds).tiles
        #expect(tiles.count == 2)
        let freeTile = tiles.first { $0.node.special == .freeSpace }
        #expect(freeTile.map { abs($0.rect.width * $0.rect.height - 60_000) < 0.01 } == true)
    }

    @Test func tinyFilesArePooledSoTheCanvasIsFullyCovered() throws {
        // One big file plus 5,000 files far below the minimum tile area.
        let tiny = files(Array(repeating: 1, count: 5_000))
        let dir = FileNode(name: "headers", type: .directory, children: tiny)
        let root = FileNode(name: "root", type: .directory, children: [dir] + files([100_000_000]))
        let result = TreemapLayout.layout(root, in: bounds)

        let covered = result.tiles.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(covered - Double(bounds.width * bounds.height)) < 1)
        #expect(result.tiles.count < 100, "tiny files share one pooled tile")
        let pool = try #require(result.tiles.first { $0.node === dir })
        #expect(pool.rect.width * pool.rect.height > 0)
    }

    @Test func squarifyKeepsAspectRatiosReasonable() {
        let rects = TreemapLayout.squarify([6, 6, 4, 3, 2, 2, 1].map { $0 * 1000.0 },
                                           in: CGRect(x: 0, y: 0, width: 150, height: 160))
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 3)
    }

    @Test func emptyAndZeroSizedNodesProduceNoTiles() {
        let root = FileNode(name: "root", type: .directory, children: [
            FileNode(name: "empty", type: .directory),
            FileNode(name: "zero", type: .file),
        ])
        #expect(TreemapLayout.layout(root, in: bounds).tiles.isEmpty)
    }
}

@Suite struct CushionRendererTests {
    @Test func cushionIsBrightestTowardTheLightAndDarkerAtTheEdges() throws {
        let image = try #require(CushionRenderer.swatch(RGB(1, 1, 1), size: CGSize(width: 100, height: 100), scale: 1))
        #expect(image.width == 100 && image.height == 100)

        let data = try #require(image.dataProvider?.data) as Data
        func brightness(_ x: Int, _ y: Int) -> Int {
            let pixel = data.withUnsafeBytes { $0.load(fromByteOffset: (y * 100 + x) * 4, as: UInt32.self) }
            return Int(pixel >> 16 & 0xFF)
        }
        let upperLeftOfCentre = brightness(40, 40)
        #expect(upperLeftOfCentre > brightness(1, 98), "lit side is brighter than the far corner")
        #expect(upperLeftOfCentre > brightness(98, 98))
        #expect(brightness(98, 98) >= 40 * 255 / 255 - 1, "never darker than ambient light")
    }
}
