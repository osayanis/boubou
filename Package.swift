// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mochi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Mochi",
            path: "Sources/Mochi",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
