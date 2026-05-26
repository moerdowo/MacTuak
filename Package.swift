// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWine",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "MacWine",
            path: "Sources/MacWine"
        )
    ]
)
