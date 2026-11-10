import AppKit
import DiskInventoryCore
import SwiftUI

/// Information panel (spec §6): details of the active window's selection.
struct InfoPanelView: View {
    private var state: AppState { AppState.shared }

    var body: some View {
        let document = state.activeDocument
        let node = document?.selection ?? document?.root
        VStack(alignment: .leading, spacing: 10) {
            if let node, let document {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                        .resizable().frame(width: 48, height: 48)
                    Text(node.name).font(.headline).lineLimit(2)
                }
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(fields(node, document), id: \.0) { title, value in
                        GridRow {
                            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                            Text(value).textSelection(.enabled).lineLimit(3)
                        }
                    }
                }
                .font(.callout)
            } else {
                Text("No selection").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minWidth: 228, idealWidth: 260, minHeight: 260, alignment: .topLeading)
    }

    private func fields(_ node: FileNode, _ document: DocumentModel) -> [(String, String)] {
        let kind = node.isDirectory && !node.isPackage ? KindClassifier.shared.folderKind : node.kindName
        var result: [(String, String)] = [
            ("Kind", kind),
            ("Size", "\(Format.bytes(node.physicalSize)) on disk"),
            ("Content", "\(Format.bytes(node.logicalSize)) (\(node.logicalSize.formatted()) bytes)"),
        ]
        if node.isDirectory { result.append(("Files", Format.count(node.fileCount))) }
        result.append(("Where", node.url.deletingLastPathComponent().path))
        let values = try? node.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        if let created = values?.creationDate { result.append(("Created", created.formatted(date: .abbreviated, time: .shortened))) }
        if let modified = values?.contentModificationDate {
            result.append(("Modified", modified.formatted(date: .abbreviated, time: .shortened)))
        }
        return result
    }
}

@MainActor
enum InfoPanel {
    static func toggle() { WindowManager.shared.toggleInfoPanel() }
}

/// Preferences (spec §8): General and Treemap pages.
struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferences().tabItem { Label("General", systemImage: "gearshape") }
            TreemapPreferences().tabItem { Label("Treemap", systemImage: "square.grid.3x3.square") }
        }
        .frame(width: 536)
    }
}

private struct GeneralPreferences: View {
    @AppStorage(Pref.showPackageContents) private var showPackageContents = false
    @AppStorage(Pref.showPhysicalFileSize) private var showPhysicalFileSize = true
    @AppStorage(Pref.splitWindowHorizontally) private var splitHorizontally = false
    @AppStorage(Pref.useSmallFontInFilesView) private var smallFiles = false
    @AppStorage(Pref.useSmallFontInKindStatisticView) private var smallKinds = false
    @AppStorage(Pref.useSmallFontInSelectionList) private var smallSelection = false
    @AppStorage(Pref.shareKindColors) private var shareKindColors = true

    var body: some View {
        Form {
            Section("View settings for new windows:") {
                Toggle("Show Package Contents", isOn: $showPackageContents)
                Toggle(isOn: $showPhysicalFileSize) {
                    Text("Show Physical File Size")
                    Text("The physical size is the space that a file occupies on a drive. Many applications show the logical size, which is the size of a file's content.")
                }
                Toggle("Split window horizontally", isOn: $splitHorizontally)
            }
            Section("Use small font in:") {
                Toggle("Files View", isOn: $smallFiles)
                Toggle("Kind Statistic Drawer", isOn: $smallKinds)
                Toggle("Selection List", isOn: $smallSelection)
            }
            Section {
                Toggle("Use the same color for each file kind in all windows", isOn: $shareKindColors)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TreemapPreferences: View {
    @AppStorage(Pref.animatedZooming) private var animatedZooming = true
    @AppStorage(Pref.showFreeSpace) private var showFreeSpace = false
    @AppStorage(Pref.showOtherSpace) private var showOtherSpace = false

    var body: some View {
        Form {
            Toggle(isOn: $animatedZooming) {
                Text("Animated Zooming")
                Text("Turn this off if the animation is too slow on your machine or if you don't like it.")
            }
            Section("View settings for new windows:") {
                Toggle(isOn: $showFreeSpace) {
                    Text("Show Free Space")
                    Text("This shows free space like a file in the treemap. It helps to see the size relations between the opened folder and the free space on the drive.")
                }
                Toggle(isOn: $showOtherSpace) {
                    Text("Show Other Space")
                    Text("This shows space used by not shown files and folders like a file in the treemap. It helps to see how the opened folder compares in size to the rest of the files on the same drive. This option is only available if not a whole drive is shown.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
