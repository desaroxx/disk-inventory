import CoreGraphics

/// Coefficients of a cushion surface z = a·x² + b·x + c·y² + d·y (van Wijk & van de Wetering 1999).
public struct CushionSurface: Sendable, Equatable {
    public var a: Double = 0, b: Double = 0, c: Double = 0, d: Double = 0

    /// Adds a parabolic ridge of height `h` spanning `rect` in both directions.
    mutating func addRidge(_ rect: CGRect, height h: Double) {
        let x1 = Double(rect.minX), x2 = Double(rect.maxX)
        let y1 = Double(rect.minY), y2 = Double(rect.maxY)
        if x2 > x1 {
            b += 4 * h * (x2 + x1) / (x2 - x1)
            a -= 4 * h / (x2 - x1)
        }
        if y2 > y1 {
            d += 4 * h * (y2 + y1) / (y2 - y1)
            c -= 4 * h / (y2 - y1)
        }
    }
}

public struct TreemapTile: Sendable {
    public let node: FileNode
    public let rect: CGRect
    public let surface: CushionSurface
}

public struct TreemapLayoutResult: Sendable {
    /// One tile per leaf, in drawing order.
    public let tiles: [TreemapTile]
    /// Rectangle of every placed node, folders included (for selection outlines and zoom animation).
    public let rects: [ObjectIdentifier: CGRect]

    public static let empty = TreemapLayoutResult(tiles: [], rects: [:])

    public func tile(at point: CGPoint) -> TreemapTile? {
        tiles.first { $0.rect.contains(point) }
    }

    public func rect(for node: FileNode) -> CGRect? { rects[node.id] }
}

public struct TreemapOptions: Sendable, Equatable {
    public var sizeMode: SizeMode = .physical
    public var showPackageContents = false
    /// Tiles smaller than this (in points²) are dropped along with their subtrees.
    public var minArea: CGFloat = 1
    /// Height of the outermost ridge.
    public var cushionHeight = 0.5
    /// Each nesting level's ridges are this fraction of the level above.
    public var cushionFalloff = 0.75

    public init(sizeMode: SizeMode = .physical, showPackageContents: Bool = false) {
        self.sizeMode = sizeMode
        self.showPackageContents = showPackageContents
    }
}

/// Squarified treemap (Bruls, Huizing, van Wijk 2000) with cushion surfaces.
public enum TreemapLayout {
    public static func layout(_ root: FileNode, in bounds: CGRect, options: TreemapOptions = .init()) -> TreemapLayoutResult {
        layout([root], in: bounds, options: options)
    }

    /// Lays out several top-level items side by side, e.g. a folder plus free-space tiles.
    public static func layout(_ items: [FileNode], in bounds: CGRect, options: TreemapOptions = .init()) -> TreemapLayoutResult {
        var builder = Builder(options: options)
        if items.count == 1, let only = items.first {
            builder.place(only, in: bounds, depth: 0, surface: CushionSurface(), isRoot: true)
        } else {
            builder.placeChildren(items, in: bounds, depth: 0, surface: CushionSurface())
        }
        return TreemapLayoutResult(tiles: builder.tiles, rects: builder.rects)
    }

    private struct Builder {
        let options: TreemapOptions
        var tiles: [TreemapTile] = []
        var rects: [ObjectIdentifier: CGRect] = [:]

        mutating func place(_ node: FileNode, in rect: CGRect, depth: Int, surface: CushionSurface, isRoot: Bool = false) {
            guard rect.width * rect.height >= options.minArea else { return }
            rects[node.id] = rect
            var surface = surface
            surface.addRidge(rect, height: options.cushionHeight * pow(options.cushionFalloff, Double(depth)))

            if !isRoot, node.isLeaf(showPackageContents: options.showPackageContents) || node.children.isEmpty {
                if node.size(options.sizeMode) > 0 {
                    tiles.append(TreemapTile(node: node, rect: rect, surface: surface))
                }
                return
            }
            placeChildren(node.children, of: node, in: rect, depth: depth + 1, surface: surface)
        }

        /// Children too small to draw are pooled into one leftover tile standing for `parent`,
        /// so a folder of many tiny files is still filled instead of leaving a hole.
        mutating func placeChildren(_ children: [FileNode], of parent: FileNode? = nil, in rect: CGRect, depth: Int,
                                    surface: CushionSurface) {
            let mode = options.sizeMode
            let sized = children.filter { $0.size(mode) > 0 }.sorted { $0.size(mode) > $1.size(mode) }
            let total = sized.reduce(0) { $0 + $1.size(mode) }
            guard total > 0 else { return }
            let scale = Double(rect.width * rect.height) / Double(total)

            var drawn: [(node: FileNode, area: Double)] = []
            var leftover = 0.0
            for child in sized {
                let area = Double(child.size(mode)) * scale
                if area >= Double(options.minArea) { drawn.append((child, area)) } else { leftover += area }
            }
            let rects = TreemapLayout.squarify(drawn.map(\.area) + (leftover > 0 ? [leftover] : []), in: rect)
            for (child, childRect) in zip(drawn.map(\.node), rects) {
                place(child, in: childRect, depth: depth, surface: surface)
            }
            if leftover > 0, let parent, let poolRect = rects.last {
                var poolSurface = surface
                poolSurface.addRidge(poolRect, height: options.cushionHeight * pow(options.cushionFalloff, Double(depth)))
                tiles.append(TreemapTile(node: parent, rect: poolRect, surface: poolSurface))
            }
        }
    }

    /// Splits `rect` into rectangles with the given areas, in input order. Squarest when the
    /// areas are sorted largest first.
    static func squarify(_ areas: [Double], in rect: CGRect) -> [CGRect] {
        var result: [CGRect] = []
        result.reserveCapacity(areas.count)
        var free = rect
        var start = 0

        while start < areas.count {
            let side = Double(min(free.width, free.height))
            var end = start + 1
            var rowSum = areas[start]
            while end < areas.count {
                let candidateSum = rowSum + areas[end]
                if worstRatio(areas[start...end], sum: candidateSum, side: side)
                    > worstRatio(areas[start..<end], sum: rowSum, side: side) { break }
                rowSum = candidateSum
                end += 1
            }
            layoutRow(areas[start..<end], sum: rowSum, in: &free, into: &result)
            start = end
        }
        return result
    }

    private static func worstRatio(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard let largest = row.max(), let smallest = row.min(), smallest > 0, sum > 0 else { return .infinity }
        let side2 = side * side, sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }

    /// Lays the row along the shorter side of `free`, then shrinks `free` by the strip it used.
    private static func layoutRow(_ row: ArraySlice<Double>, sum: Double, in free: inout CGRect,
                                  into result: inout [CGRect]) {
        if free.width >= free.height {
            let stripWidth = free.height > 0 ? CGFloat(sum) / free.height : 0
            var y = free.minY
            for area in row {
                let h = stripWidth > 0 ? CGFloat(area) / stripWidth : 0
                result.append(CGRect(x: free.minX, y: y, width: stripWidth, height: h))
                y += h
            }
            free = CGRect(x: free.minX + stripWidth, y: free.minY,
                          width: max(0, free.width - stripWidth), height: free.height)
        } else {
            let stripHeight = free.width > 0 ? CGFloat(sum) / free.width : 0
            var x = free.minX
            for area in row {
                let w = stripHeight > 0 ? CGFloat(area) / stripHeight : 0
                result.append(CGRect(x: x, y: free.minY, width: w, height: stripHeight))
                x += w
            }
            free = CGRect(x: free.minX, y: free.minY + stripHeight,
                          width: free.width, height: max(0, free.height - stripHeight))
        }
    }
}
