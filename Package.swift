// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xeneon-toolbox",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "XeneonTouchCore"),
        .target(
            name: "XeneonTouchDriver",
            dependencies: ["XeneonTouchCore"]
        ),
        .target(name: "ToolboxKit"),
        .executableTarget(
            name: "xeneon-touch",
            dependencies: ["XeneonTouchCore", "XeneonTouchDriver"]
        ),
        .executableTarget(
            name: "XeneonToolbox",
            dependencies: ["XeneonTouchCore", "XeneonTouchDriver", "ToolboxKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "XeneonTouchCoreTests",
            dependencies: ["XeneonTouchCore"]
        ),
    ]
)
