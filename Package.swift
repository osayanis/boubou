// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PetiteBoule",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PetiteBoule",
            path: "Sources/PetiteBoule",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
