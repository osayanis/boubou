// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Boubou",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Boubou",
            path: "Sources/Boubou",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
