import AppKit
import DiskInventoryCore
import SwiftUI

/// File Kind Statistics (spec §4): colour swatch, kind, total size and file count per kind.
struct KindStatisticsView: View {
    let document: DocumentModel
    @AppStorage(Pref.useSmallFontInKindStatisticView) private var smallFont = false
    @State private var sortOrder = [KeyPathComparator(\Row.size, order: .reverse)]
    @State private var selectedKind: String?

    struct Row: Identifiable {
        let kindName: String
        let size: Int64
        let fileCount: Int
        let color: RGB
        var id: String { kindName }
    }

    private var rows: [Row] {
        _ = document.colorsVersion
        return document.kindStatistics.map {
            Row(kindName: $0.kindName, size: $0.size(document.sizeMode), fileCount: $0.fileCount,
                color: document.colors.color(forKind: $0.kindName))
        }.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selectedKind, sortOrder: $sortOrder) {
            TableColumn("Color") { row in
                Image(nsImage: Swatch.image(row.color))
            }
            .width(44)
            TableColumn("Kind", value: \.kindName) { row in
                Text(row.kindName).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 60, ideal: 150)
            TableColumn("Size", value: \.size) { row in
                Text(Format.bytes(row.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 72)
            TableColumn("Files", value: \.fileCount) { row in
                Text(Format.count(row.fileCount)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 40, ideal: 50)
        }
        .font(smallFont ? .system(size: NSFont.smallSystemFontSize) : .body)
        .contextMenu(forSelectionType: String.self) { kinds in
            Button("Show Files in Selection List") {
                document.selectionListKind = kinds.first
                document.showSelectionList = true
            }
            .disabled(kinds.isEmpty)
        }
    }
}

/// Small cushion images for the Color column, cached per colour.
@MainActor
enum Swatch {
    private static var cache: [RGB: NSImage] = [:]

    static func image(_ rgb: RGB) -> NSImage {
        if let hit = cache[rgb] { return hit }
        let size = CGSize(width: 28, height: 12)
        let image = CushionRenderer.swatch(rgb, size: size, scale: 2)
            .map { NSImage(cgImage: $0, size: size) } ?? NSImage(size: size)
        cache[rgb] = image
        return image
    }
}
