import Foundation

/// UserDefaults keys and defaults (spec §8).
enum Pref {
    static let showPackageContents = "ShowPackageContents"
    static let showPhysicalFileSize = "ShowPhysicalFileSize"
    static let splitWindowHorizontally = "SplitWindowHorizontally"
    static let useSmallFontInFilesView = "UseSmallFontInFilesView"
    static let useSmallFontInKindStatisticView = "UseSmallFontInKindStatisticView"
    static let useSmallFontInSelectionList = "UseSmallFontInSelectionList"
    static let shareKindColors = "ShareKindColors"
    static let animatedZooming = "AnimatedZooming"
    static let showFreeSpace = "ShowFreeSpace"
    static let showOtherSpace = "ShowOtherSpace"
    static let dontShowPrivacyInfo = "DontShowPrivacyInfo"
    static let recentFolders = "RecentFolders"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showPackageContents: false,
            showPhysicalFileSize: true,
            splitWindowHorizontally: false,
            useSmallFontInFilesView: false,
            useSmallFontInKindStatisticView: false,
            useSmallFontInSelectionList: false,
            shareKindColors: true,
            animatedZooming: true,
            showFreeSpace: false,
            showOtherSpace: false,
            dontShowPrivacyInfo: false,
        ])
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func count(_ n: Int) -> String {
        n.formatted(.number)
    }
}
