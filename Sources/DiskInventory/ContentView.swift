import DiskInventoryCore
import SwiftUI

struct ContentView: View {
    @State private var model = ScanModel()
    @State private var choosingFolder = false

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            StatusBar(model: model)
        }
        .toolbar {
            ToolbarItemGroup {
                if model.isScanning {
                    Button("Stop", systemImage: "stop.fill") { model.cancel() }
                } else {
                    Button("Choose Folder…", systemImage: "folder") { choosingFolder = true }
                        .keyboardShortcut("o")
                }
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.scan(url) }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            ContentUnavailableView {
                Label("No Folder Scanned", systemImage: "internaldrive")
            } description: {
                Text("Choose a folder or volume to see what is using the space.")
            } actions: {
                Button("Choose Folder…") { choosingFolder = true }
            }
        case .scanning(let url, _, _):
            ProgressView("Scanning \(url.path)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let url, let message):
            ContentUnavailableView("Couldn't scan \(url.lastPathComponent)",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .done(_, let root, _):
            HSplitView {
                FileOutlineView(root: root, selection: $model.selection)
                    .frame(minWidth: 320, idealWidth: 380)
                TreemapView(root: root, selection: $model.selection)
                    .frame(minWidth: 400)
            }
        }
    }
}

private struct StatusBar: View {
    let model: ScanModel

    var body: some View {
        HStack {
            Text(text).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let selected = model.selection {
                Text("\(selected.name) — \(Format.bytes(selected.size))").lineLimit(1)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var text: String {
        switch model.state {
        case .idle: "Ready"
        case .scanning(_, let files, let bytes): "\(Format.count(files)) files, \(Format.bytes(bytes))"
        case .failed(_, let message): message
        case .done(let url, let root, let duration):
            "\(url.path): \(Format.count(root.fileCount)) files, \(Format.bytes(root.size)) "
                + "(scanned in \(duration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))))"
        }
    }
}
