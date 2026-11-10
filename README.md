# DiskInventory

A macOS disk usage browser with a file outline and a squarified treemap, in the style of Disk Inventory X.

## Run

```sh
swift run DiskInventory                    # launch; the Volumes window lists drives
swift run DiskInventory -open ~/Downloads  # scan a folder straight away
swift test                                 # core tests
open Package.swift                         # open in Xcode
```

Use `-open <path>` rather than a bare path: an executable without an app bundle swallows a
bare path as an open-file request.

To scan protected folders such as `~/Library` or other users' homes, grant Full Disk Access
to the app (or to Terminal/Xcode when running from there).

### Checking the UI without clicking

`DI_SNAPSHOT=/tmp/shot` saves a PNG of every window once the first folder has loaded.
`DI_SCRIPT` then runs steps against it and saves the windows after each one, for example:

```sh
DI_SNAPSHOT=/tmp/shot DI_SCRIPT=selectLargestFile,kinds,list,info,zoomIn,zoomOut \
  swift run DiskInventory -open ~/Downloads
```

Steps: `selectLargestFile selectParent hoverSelection zoomIn zoomOut kinds list info packages
logical free other split`. The app quits when the script ends.

## Layout

| Path | What |
|---|---|
| `docs/SPEC.md` | Clean-room behaviour spec of the reference app, from its shipped resources. |
| `Sources/DiskInventoryCore/Scanner.swift` | Parallel `getattrlistbulk(2)` walk: physical and logical sizes, hard links once, no symlinks or other volumes. |
| `Sources/DiskInventoryCore/FileNode.swift` | Immutable size tree with parent links; edits rebuild the ancestors. |
| `Sources/DiskInventoryCore/FileKinds.swift` | Finder kinds per extension, kind statistics, the 12-colour kind palette. |
| `Sources/DiskInventoryCore/TreemapLayout.swift` | Squarified layout with cushion surfaces; tiny files pooled per folder. |
| `Sources/DiskInventoryCore/CushionRenderer.swift` | Shades the tiles into a bitmap. |
| `Sources/DiskInventory/` | The app: windows, files view, treemap view, panels, menus, preferences. |
| `Tests/DiskInventoryCoreTests/` | Core tests. |

## Known gaps

- No app bundle yet: no icon, and folders dropped on the Dock icon are not opened.
- The selection list's search scope is a popup beside the field, not the field's own menu.
