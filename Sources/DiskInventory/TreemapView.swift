import DiskInventoryCore
import SwiftUI

struct TreemapView: View {
    let root: FileNode
    @Binding var selection: FileNode?

    @State private var tiles: [TreemapTile] = []
    @State private var layoutKey: LayoutKey?

    private struct LayoutKey: Equatable {
        let root: ObjectIdentifier
        let size: CGSize
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, _ in
                for tile in tiles {
                    let rect = tile.rect.insetBy(dx: 0.5, dy: 0.5)
                    let base = TileColor.color(forExtension: tile.node.fileExtension)
                    // Simple top-left highlight; a cushion shader is the next step for the classic look.
                    context.fill(Path(rect), with: .linearGradient(
                        Gradient(colors: [base.opacity(0.75), base]),
                        startPoint: rect.origin, endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
                }
                if let selection, let tile = tiles.first(where: { $0.node === selection }) {
                    context.stroke(Path(tile.rect.insetBy(dx: 1, dy: 1)), with: .color(.white), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                selection = tiles.first { $0.rect.contains(location) }?.node
            }
            .task(id: LayoutKey(root: root.id, size: geometry.size)) {
                await relayout(size: geometry.size)
            }
        }
        .background(.black)
    }

    private func relayout(size: CGSize) async {
        let key = LayoutKey(root: root.id, size: size)
        guard key != layoutKey, size.width > 0, size.height > 0 else { return }
        let root = root
        // Debounce live window resizes; `.task(id:)` cancels this when the size changes again.
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return }
        let result = await Task.detached(priority: .userInitiated) {
            TreemapLayout.layout(root, in: CGRect(origin: .zero, size: size), minArea: 2)
        }.value
        guard !Task.isCancelled else { return }
        tiles = result
        layoutKey = key
    }
}

enum TileColor {
    private static let palette: [Color] = [
        .init(red: 0.86, green: 0.30, blue: 0.30), .init(red: 0.30, green: 0.62, blue: 0.86),
        .init(red: 0.36, green: 0.74, blue: 0.40), .init(red: 0.92, green: 0.66, blue: 0.24),
        .init(red: 0.62, green: 0.42, blue: 0.82), .init(red: 0.26, green: 0.74, blue: 0.72),
        .init(red: 0.88, green: 0.46, blue: 0.68), .init(red: 0.66, green: 0.66, blue: 0.30),
    ]

    /// Stable color per extension. FNV-1a, because `String.hashValue` is randomized per launch.
    static func color(forExtension ext: String) -> Color {
        guard !ext.isEmpty else { return .gray }
        var hash: UInt32 = 2_166_136_261
        for byte in ext.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return palette[Int(hash % UInt32(palette.count))]
    }
}
