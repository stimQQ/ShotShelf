// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShotShelf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShotShelf",
            path: "Sources/ShotShelf"
        )
    ]
)
