// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskInventory",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DiskInventory", targets: ["DiskInventory"]),
        .library(name: "DiskInventoryCore", targets: ["DiskInventoryCore"]),
    ],
    targets: [
        .target(name: "DiskInventoryCore"),
        .executableTarget(name: "DiskInventory", dependencies: ["DiskInventoryCore"]),
        .testTarget(name: "DiskInventoryCoreTests", dependencies: ["DiskInventoryCore"]),
    ]
)
