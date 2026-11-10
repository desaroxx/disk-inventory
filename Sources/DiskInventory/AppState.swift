import AppKit
import DiskInventoryCore
import Observation
import UniformTypeIdentifiers

/// App-wide state: open documents, the window that menu commands act on, recent folders.
@MainActor @Observable
final class AppState {
    static let shared = AppState()

    private(set) var documents: [UUID: DocumentModel] = [:]
    /// The document window that was key most recently. Menu commands and the Information
    /// panel follow it, so they keep working while a panel is key.
    var activeDocumentID: UUID?
    var isInfoPanelVisible = false
    private(set) var recentFolders: [URL] = []

    let sharedColors = KindColorRegistry()

    private init() {
        recentFolders = (UserDefaults.standard.stringArray(forKey: Pref.recentFolders) ?? []).map { URL(filePath: $0) }
    }

    var activeDocument: DocumentModel? { activeDocumentID.flatMap { documents[$0] } }

    func document(_ id: UUID) -> DocumentModel? { documents[id] }

    /// Starts scanning `url` and returns the new document's ID, or nil if the user backed out.
    func startScan(_ url: URL) -> UUID? {
        guard confirmPrivacyAccess(for: url) else { return nil }
        let colors = Pref.bool(Pref.shareKindColors) ? sharedColors : KindColorRegistry()
        let document = DocumentModel(url: url, colors: colors)
        documents[document.id] = document
        noteRecent(url)
        document.load()
        return document.id
    }

    func close(_ id: UUID) {
        documents[id]?.cancel()
        documents[id] = nil
        if activeDocumentID == id { activeDocumentID = nil }
    }

    /// Runs the Open panel for a folder, volume or package.
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.folder, .package, .volume]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Recent folders

    private func noteRecent(_ url: URL) {
        recentFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentFolders.insert(url, at: 0)
        recentFolders = Array(recentFolders.prefix(10))
        UserDefaults.standard.set(recentFolders.map(\.path), forKey: Pref.recentFolders)
    }

    func clearRecentFolders() {
        recentFolders = []
        UserDefaults.standard.removeObject(forKey: Pref.recentFolders)
    }

    // MARK: Privacy notice (spec §1)

    private func confirmPrivacyAccess(for url: URL) -> Bool {
        guard !Pref.bool(Pref.dontShowPrivacyInfo), Self.containsPrivacyProtectedFolders(url) else { return true }
        let alert = NSAlert()
        alert.messageText = "Some folders which will be scanned contain private files. The access is protected by the macOS privacy protection."
        alert.informativeText = """
            Upon first access macOS will ask whether you allow access to these folders and files.

            No data will be read - just information like file sizes and types are collected.
            """
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not show this information again."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: Pref.dontShowPrivacyInfo)
        }
        return response == .alertFirstButtonReturn
    }

    static func containsPrivacyProtectedFolders(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let protected = ["Desktop", "Documents", "Downloads", "Pictures", "Library/Calendars", "Library/Reminders",
                         "Library/Application Support/AddressBook"].map { home + "/" + $0 }
        let path = url.standardizedFileURL.path
        let target = path.hasSuffix("/") ? path : path + "/"
        return protected.contains { ($0 + "/").hasPrefix(target) || target.hasPrefix($0 + "/") }
            || path.hasPrefix("/Volumes/")
    }
}
