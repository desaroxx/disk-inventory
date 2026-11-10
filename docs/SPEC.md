# Behaviour spec

Clean-room description of the reference app (Disk Inventory X 1.3), taken from its shipped
resources only: Interface Builder archives decoded with REA, `Info.plist`, the toolbar plist,
`Localizable.strings`, the bundled help page and its screenshot. No source code or decompiled
code was read. Everything here describes *what* the app does; the implementation is our own.

Legend: **[obs]** observed in a shipped resource · **[inf]** inferred from names or the help
screenshot · **[ours]** our design decision where the reference is silent or obsolete.

## 1. Documents and launch

- Each opened folder is a separate document window. Folders, volumes, `.app` and `.plugin`
  bundles can be opened (dropped on the Dock icon or via Open). [obs: `CFBundleDocumentTypes`]
- **Volumes panel** ("DrivesPanel") [obs: `VolumesPanel.nib`]: a 532×263 window listing mounted
  volumes in a table with 45 pt rows and columns *icon* (45×45), *volume* (name), *usage* and
  *usagePercent* (a usage bar). Below the table: a box labelled "Select Folder:" with a "…"
  button (runs Open Folder), and a default button "Open Volume", enabled only when a row is
  selected. Shown at launch [inf].
- **Loading panel** [obs: `LoadingPanel.nib`]: window titled "Loading folder contents...",
  408×153, with a multi-line text field (current path), a progress bar, and a Cancel button.
  A second phase shows "Classifying Files..." [obs: strings].
- Before scanning folders protected by macOS privacy (Desktop, Documents, Downloads, Calendars,
  Contacts, Photos, removable and network volumes), an explanatory alert is shown once, with a
  "Do not show this information again." checkbox. [obs: strings]

## 2. Main window [obs: `TreeMap.nib`]

- Default size 572×521, frame autosaved. Title: `<folder name> (<total size>)` [inf: screenshot].
- Content: a split view (vertical divider by default; *Split Horizontally* stacks them) with:
  - **Files view** (left/top): outline view, columns **Name** (`displayName`, 181 pt, icon +
    name) and **Size** (57 pt). Row height 17. Children sorted by size, largest first.
    Columns autosave as "FilesView".
  - **Treemap** (right/bottom): initial first responder.
- Below the split view, two text lines describing the item **under the mouse pointer** in the
  treemap [obs + help]:
  1. `name (relative/folder/path)` e.g. `Delivery (PrelimBinaries/Delivery 1.0)`
  2. `kind, size` e.g. `Application, 5,0 MB` (smaller font)
- Selection is synchronised between files view and treemap. Selecting a folder selects its
  whole rectangle in the treemap.

### Context menu (files view, treemap, selection list) [obs]

Open · Open With ▸ (default app first, separator, other apps) · — · Reveal in Finder ·
Refresh · — · Move To Trash · — · Zoom In · Zoom Out

### Toolbar [obs: `MainWindowToolbar.toolbar`]

Default: Zoom In · Zoom Out · ⟷ flexible space · Show File Kind Statistics.
Also allowed: Show Information, Preferences, Show Package Contents (two-state image),
Reveal in Finder, Refresh Selection, Refresh All, Move to Trash. Customisable.

## 3. Treemap [obs: help text + screenshot; rendering details ours]

- Squarified layout, cushion shading (`TMVCushionRenderer`). Every file is a shaded cushion;
  nested folders add ridges so hierarchy is visible.
- Selected item outlined with a yellow rectangle.
- Hover updates the two status lines.
- **Zoom In** makes the selected folder the treemap root (animated if *Animated Zooming*);
  **Zoom Out** goes up one level; **View ▸ Zoom Out To ▸** lists every level on the zoom stack.
- **Show Free Space**: adds a tile "free space on drive". **Show Other Space**: adds a tile
  "space occupied by other files and folders" (only when not showing a whole volume).

## 4. File kinds and colours [obs: help + screenshot]

- Every file has a *kind* (the Finder kind, e.g. "Application", "HTML document").
  [ours: `URLResourceValues.localizedTypeDescription`; "Ignore Creator Code" is obsolete
  because creator codes no longer exist, so the menu item is dropped.]
- 12 colours assigned to the 12 largest kinds by total size; all other kinds are grey. In
  the screenshot the 12 are six saturated hues (blue, red, green, cyan, magenta, yellow)
  followed by lighter variants of the same six in the same order.
- With *ShareKindColors* (default on), assignments are shared across all windows and never
  reset until relaunch; a later window whose kinds are all new gets grey for everything.

### File Kind Statistics drawer [obs]

Side panel (drawer, 305 pt wide) with a table autosaved as "KindStatisticView":
**Color** (35 pt, cushion swatch) · **Kind** · **Size** · **Files**. Default sort size
descending; all columns sortable. Context menu: "Show Files in Selection List".

## 5. Selection List drawer [obs]

Bottom drawer (456×167). Header row: label "Show all files of kind:", a popup listing the
kinds (bound to the kind statistics; first item "(all kinds)"), a spinner, and a search
field (placeholder "search") whose menu chooses All / Name / Kind / Path. Table autosaved
as "SelectionList": **Name** · **Size** · **Path** (containing folder). Shares the context menu.

## 6. Information panel [obs: `InfoPanel.nib`]

Utility panel "Information" (228×260): 48×48 icon, file name, then a list of titled values
for the selection [inf: kind, size, path, creation/modification dates].

## 7. Menus [obs: `MainMenu.nib`]

- **App**: About · — · Preferences… ⌘, · — · Services · — · Hide ⌘H · Hide Others ⌥⌘H ·
  Show All · — · Quit ⌘Q
- **File**: Open Folder… ⌘O · Open Recent ▸ · — · Close ⌘W · — · Reveal in Finder ⇧⌘F ·
  Refresh Selection · Refresh All · — · Move To Trash ⌘⌫
- **Edit**: standard (Undo/Redo, Cut/Copy/Paste/Delete/Select All, Find ▸, Spelling ▸)
- **View**: Zoom In ⌘+ · Zoom Out ⌘- · Zoom Out To ▸ · — · Select Parent Folder ⌘U · — ·
  Show/Hide Free Space · Show/Hide Other Space · — · Show/Hide Package Contents ·
  Show Physical/Logical File Size · (Ignore Creator Code) · — · Split Horizontally/Vertically ·
  — · Hide Toolbar · Customize Toolbar…
- **Window**: Show/Hide File Kind Statistics · Show/Hide Selection List · — · Information ⌘I ·
  — · Minimize ⌘M · Bring All to Front
- **Help**: Help ⌘? · Visit Website
- Toggle items flip their titles (e.g. "Show Free Space" ↔ "Hide Free Space"). [obs: strings]

## 8. Preferences [obs: `Info.plist`, preference nibs]

`UserDefaults` keys and defaults; checkboxes bound directly to them. Most apply to *new
windows* ("View settings for new windows:"); the View menu changes the current window.

| Key | Default | Page |
|---|---|---|
| `ShowPackageContents` | false | General |
| `IgnoreCreatorCode` | false | General (dropped, see §4) |
| `ShowPhysicalFileSize` | true | General: "The physical size is the space that a file occupies on a drive. Many applications show the logical size, which is the size of a file's content." |
| `SplitWindowHorizontally` | false | General |
| `UseSmallFontInFilesView` | false | General ("Use small font in:") |
| `UseSmallFontInKindStatisticView` | false | General |
| `UseSmallFontInSelectionList` | false | General |
| `ShareKindColors` | true | General: "Use the same color for each file kind in all windows" |
| `AnimatedZooming` | true | Treemap |
| `ShowFreeSpace` | false | Treemap |
| `ShowOtherSpace` | false | Treemap |

Pages: General, Treemap (Finder Plugin page is hidden; not cloned).

## 9. Errors [obs: strings]

- `"%@" does not exist any more.` (stale item on refresh/reveal)
- `"%@" cannot be moved to the trash by Disk Inventory X.` + `Maybe you do not have
  sufficient access privileges.`
- `The folder's content could not be loaded.` / `The volume has been ejected during loading
  of folder centents.`

## Not cloned

Branding (name, icon, About box, website, donation panel), the Finder context-menu plugin,
creator-code handling.
