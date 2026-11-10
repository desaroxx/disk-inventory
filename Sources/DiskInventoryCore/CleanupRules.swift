import Foundation

/// How sure a rule is that its matches can go.
public enum CleanupRisk: Sendable, Comparable {
    /// Rebuilt or re-downloaded automatically when needed.
    case safe
    /// Probably unneeded, but only the user can tell.
    case review
}

/// One kind of space that is usually safe to reclaim, such as Xcode's DerivedData.
public struct CleanupRule: Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Why matches can go, shown with every suggestion.
    public let explanation: String
    public let risk: CleanupRisk
    let matcher: Matcher

    enum Matcher: Sendable {
        /// The folder at this absolute path.
        case folder(String)
        /// Each item directly inside the folder at this absolute path.
        case eachItem(in: String)
        /// A folder with this name next to a file with the marker name, e.g. `node_modules` beside `package.json`.
        case buildOutput(name: String, besideFile: String)
        /// Items of at least `minSize` bytes directly inside the folder at this path: with `minAge`,
        /// those not modified for that many seconds; without it, those with one of `extensions`.
        case downloads(in: String, minSize: Int64, minAge: TimeInterval?, extensions: Set<String>)
    }

    /// `parentPath` is the absolute path of the folder holding `node`.
    func matches(_ node: FileNode, parentPath: String, now: Date) -> Bool {
        switch matcher {
        case .folder(let path):
            return node.isDirectory && parentPath == (path as NSString).deletingLastPathComponent
                && node.name == (path as NSString).lastPathComponent
        case .eachItem(let path):
            return parentPath == path
        case .buildOutput(let name, let marker):
            return node.isDirectory && node.name == name
                && (node.parent?.children.contains { !$0.isDirectory && $0.name == marker } ?? false)
        case .downloads(let path, let minSize, let minAge, let extensions):
            guard parentPath == path, node.physicalSize >= minSize else { return false }
            if let minAge {
                guard let modified = node.modificationDate else { return false }
                return now.timeIntervalSince(modified) >= minAge
            }
            return extensions.contains((node.name as NSString).pathExtension.lowercased())
        }
    }
}

/// An item a rule suggests removing.
public struct CleanupCandidate: Sendable, Identifiable {
    public let node: FileNode
    public let rule: CleanupRule
    /// Absolute path; stays the same when the tree is rebuilt.
    public let path: String
    public var id: String { path }
}

extension CleanupRule {
    /// The built-in rules for a user whose home folder is `home`. Earlier rules win.
    public static func standard(home: String) -> [CleanupRule] {
        let library = home + "/Library"
        let xcode = library + "/Developer/Xcode"
        let day: TimeInterval = 86_400
        return [
            CleanupRule(id: "derivedData", title: "Xcode build data",
                        explanation: "Xcode rebuilds DerivedData the next time you build.",
                        risk: .safe, matcher: .folder(xcode + "/DerivedData")),
            CleanupRule(id: "deviceSupport", title: "Xcode device support",
                        explanation: "Xcode downloads it again when the device is connected.",
                        risk: .safe, matcher: .eachItem(in: xcode + "/iOS DeviceSupport")),
            CleanupRule(id: "simulatorCaches", title: "Simulator caches",
                        explanation: "The simulator recreates its caches.",
                        risk: .safe, matcher: .folder(library + "/Developer/CoreSimulator/Caches")),
            CleanupRule(id: "archives", title: "Xcode archives",
                        explanation: "Only needed to re-export an old build or read its crash reports.",
                        risk: .review, matcher: .eachItem(in: xcode + "/Archives")),
            CleanupRule(id: "caches", title: "App caches",
                        explanation: "Apps recreate their caches. Quit the app first.",
                        risk: .safe, matcher: .eachItem(in: library + "/Caches")),
            CleanupRule(id: "nodeModules", title: "node_modules",
                        explanation: "npm install restores it from package.json.",
                        risk: .safe, matcher: .buildOutput(name: "node_modules", besideFile: "package.json")),
            CleanupRule(id: "swiftBuild", title: "Swift build folders",
                        explanation: "swift build recreates .build.",
                        risk: .safe, matcher: .buildOutput(name: ".build", besideFile: "Package.swift")),
            CleanupRule(id: "rustTarget", title: "Rust build folders",
                        explanation: "cargo build recreates target.",
                        risk: .safe, matcher: .buildOutput(name: "target", besideFile: "Cargo.toml")),
            CleanupRule(id: "installers", title: "Installers in Downloads",
                        explanation: "Disk images and installers are rarely needed after installing.",
                        risk: .review,
                        matcher: .downloads(in: home + "/Downloads", minSize: 10_000_000, minAge: nil,
                                            extensions: ["dmg", "pkg", "iso", "xip"])),
            CleanupRule(id: "oldDownloads", title: "Old large downloads",
                        explanation: "Over 100 MB and not modified for 3 months.",
                        risk: .review,
                        matcher: .downloads(in: home + "/Downloads", minSize: 100_000_000, minAge: 90 * day,
                                            extensions: [])),
        ]
    }

    /// Items under `root` that `rules` suggest removing, largest first. Nothing inside a
    /// suggested item is suggested again, and the root itself is never suggested.
    public static func candidates(in root: FileNode, rules: [CleanupRule], now: Date = .now) -> [CleanupCandidate] {
        var result: [CleanupCandidate] = []
        func join(_ parent: String, _ name: String) -> String {
            parent.hasSuffix("/") ? parent + name : parent + "/" + name
        }
        func visit(_ folder: FileNode, path: String) {
            for child in folder.children {
                if let rule = rules.first(where: { $0.matches(child, parentPath: path, now: now) }) {
                    result.append(CleanupCandidate(node: child, rule: rule, path: join(path, child.name)))
                } else if child.isDirectory {
                    visit(child, path: join(path, child.name))
                }
            }
        }
        visit(root, path: root.url.standardizedFileURL.path)
        return result.sorted { $0.node.physicalSize > $1.node.physicalSize }
    }
}
