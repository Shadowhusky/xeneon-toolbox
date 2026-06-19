// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xeneon-toolbox",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jamesrochabrun/SwiftOpenAI", from: "4.4.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),
    ],
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
            dependencies: [
                "XeneonTouchCore", "XeneonTouchDriver", "ToolboxKit",
                .product(name: "SwiftOpenAI", package: "SwiftOpenAI"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "XeneonTouchCoreTests",
            dependencies: ["XeneonTouchCore"]
        ),
        .testTarget(
            name: "ToolboxKitTests",
            dependencies: ["ToolboxKit"]
        ),
    ]
)
