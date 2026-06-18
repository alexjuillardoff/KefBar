// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KefBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KefBar",
            path: "Sources/KefBar"
        )
    ]
)
