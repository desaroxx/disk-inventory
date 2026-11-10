# DiskInventory

A macOS disk usage browser with a file outline and a squarified treemap, in the style of Disk Inventory X.

## Run

```sh
swift run DiskInventory   # launch the app
swift test                # run the core tests
open Package.swift        # open in Xcode
```

To scan protected folders such as `~/Library` or other users' homes, grant Full Disk Access
to the app (or to Terminal/Xcode when running from there).

## Layout

| Path | What |
|---|---|
| `Sources/DiskInventoryCore/Scanner.swift` | Parallel directory walk using `getattrlistbulk(2)`. Counts allocated size, counts hard links once, doesn't follow symlinks or cross mount points. |
| `Sources/DiskInventoryCore/FileNode.swift` | Immutable tree with sizes rolled up and children sorted largest first. |
| `Sources/DiskInventoryCore/TreemapLayout.swift` | Squarified treemap layout (Bruls et al. 2000). |
| `Sources/DiskInventory/` | SwiftUI app: `NSOutlineView` file list, `Canvas` treemap, scan state. |
| `Tests/DiskInventoryCoreTests/` | Scanner and layout tests. |

## Next steps

- Cushion shading for treemap tiles (van Wijk & van de Wetering 1999).
- Kind/extension legend with sizes per type.
- Reveal in Finder, Quick Look, Move to Trash, with the tree updated in place.
- App bundle target (Info.plist, icon, signing) for distribution.
- Handle APFS firmlinks when scanning `/`.
