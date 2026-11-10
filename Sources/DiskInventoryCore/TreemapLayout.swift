import CoreGraphics

public struct TreemapTile: Sendable {
    public let node: FileNode
    public let rect: CGRect
    public let depth: Int
}

/// Squarified treemap (Bruls, Huizing, van Wijk 2000). Emits one tile per non-directory
/// node, with directories subdividing their own rectangle.
public enum TreemapLayout {
    /// - Parameter minArea: tiles smaller than this (in points²) are dropped, along with their subtrees.
    public static func layout(_ root: FileNode, in bounds: CGRect, minArea: CGFloat = 1) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        place(root, in: bounds, depth: 0, minArea: minArea, into: &tiles)
        return tiles
    }

    private static func place(_ node: FileNode, in rect: CGRect, depth: Int, minArea: CGFloat,
                              into tiles: inout [TreemapTile]) {
        guard rect.width * rect.height >= minArea else { return }
        guard node.isDirectory else {
            tiles.append(TreemapTile(node: node, rect: rect, depth: depth))
            return
        }
        let children = node.children.filter { $0.size > 0 }
        guard node.size > 0, !children.isEmpty else { return }

        let scale = Double(rect.width * rect.height) / Double(node.size)
        let areas = children.map { Double($0.size) * scale }
        for (child, childRect) in zip(children, squarify(areas, in: rect)) {
            place(child, in: childRect, depth: depth + 1, minArea: minArea, into: &tiles)
        }
    }

    /// Splits `rect` into rectangles with the given areas (sorted largest first), in input order.
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
        guard let largest = row.first, let smallest = row.last, smallest > 0, sum > 0 else { return .infinity }
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
