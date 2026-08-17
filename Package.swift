// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AIMeter",
            path: "Sources/AIMeter",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
