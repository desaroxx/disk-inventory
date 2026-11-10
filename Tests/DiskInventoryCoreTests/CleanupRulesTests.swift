import Foundation
import Testing
@testable import DiskInventoryCore

@Suite struct CleanupRulesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let rules = CleanupRule.standard(home: "/Users/test")

    func file(_ name: String, _ size: Int64, daysOld: Double = 0) -> FileNode {
        FileNode(name: name, type: .file, physicalSize: size, logicalSize: size,
                 modificationDate: now.addingTimeInterval(-daysOld * 86_400))
    }

    func dir(_ name: String, _ children: [FileNode]) -> FileNode {
        FileNode(name: name, type: .directory, children: children)
    }

    func home(_ children: [FileNode]) -> FileNode {
        FileNode(name: "test", type: .directory, children: children, url: URL(filePath: "/Users/test"))
    }

    func suggestions(_ root: FileNode) -> [String: String] {
        Dictionary(uniqueKeysWithValues: CleanupRule.candidates(in: root, rules: rules, now: now).map { ($0.path, $0.rule.id) })
    }

    @Test func findsXcodeDataAndEachCacheSeparately() {
        let root = home([
            dir("Library", [
                dir("Developer", [dir("Xcode", [dir("DerivedData", [file("x", 500)])])]),
                dir("Caches", [dir("com.app.one", [file("a", 10)]), dir("com.app.two", [file("b", 20)])]),
            ]),
        ])
        #expect(suggestions(root) == [
            "/Users/test/Library/Developer/Xcode/DerivedData": "derivedData",
            "/Users/test/Library/Caches/com.app.one": "caches",
            "/Users/test/Library/Caches/com.app.two": "caches",
        ])
    }

    @Test func buildOutputNeedsItsProjectFileAndIsNotSuggestedTwice() {
        let project = dir("web", [
            file("package.json", 1),
            dir("node_modules", [dir("dep", [file("package.json", 1), dir("node_modules", [file("y", 9)])])]),
        ])
        let stray = dir("notes", [dir("node_modules", [file("z", 9)])])
        let swift = dir("tool", [file("Package.swift", 1), dir(".build", [file("bin", 50)])])
        #expect(suggestions(home([project, stray, swift])) == [
            "/Users/test/web/node_modules": "nodeModules",
            "/Users/test/tool/.build": "swiftBuild",
        ])
    }

    @Test func downloadsNeedSizeAndAgeOrAnInstallerExtension() {
        let root = home([dir("Downloads", [
            file("old-video.mov", 200_000_000, daysOld: 120),
            file("new-video.mov", 200_000_000, daysOld: 5),
            file("old-small.pdf", 1_000, daysOld: 400),
            file("Setup.DMG", 50_000_000),
            file("tiny.pkg", 1_000),
            dir("old-folder", [file("part", 150_000_000, daysOld: 200)]),
        ])])
        #expect(suggestions(root) == [
            "/Users/test/Downloads/old-video.mov": "oldDownloads",
            "/Users/test/Downloads/Setup.DMG": "installers",
            "/Users/test/Downloads/old-folder": "oldDownloads",
        ])
    }

    @Test func worksWhenTheScanStartsBelowHomeAndNeverSuggestsTheRoot() {
        let caches = FileNode(name: "Caches", type: .directory, children: [dir("com.app", [file("a", 10)])],
                              url: URL(filePath: "/Users/test/Library/Caches"))
        #expect(suggestions(caches) == ["/Users/test/Library/Caches/com.app": "caches"])
        let derived = FileNode(name: "DerivedData", type: .directory, children: [file("x", 1)],
                               url: URL(filePath: "/Users/test/Library/Developer/Xcode/DerivedData"))
        #expect(suggestions(derived).isEmpty)
    }

    @Test func largestFirst() {
        let root = home([dir("Library", [dir("Caches", [dir("small", [file("a", 10)]), dir("big", [file("b", 99)])])])])
        #expect(CleanupRule.candidates(in: root, rules: rules, now: now).map(\.node.name) == ["big", "small"])
    }

    @Test func directoriesCarryTheirNewestModificationDate() {
        let folder = dir("f", [file("a", 1, daysOld: 10), file("b", 1, daysOld: 2)])
        #expect(folder.modificationDate == now.addingTimeInterval(-2 * 86_400))
    }
}
