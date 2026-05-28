// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacTuak",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "MacTuak",
            path: "Sources/MacTuak"
        )
    ]
)
