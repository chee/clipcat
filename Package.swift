// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipCat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipCat",
            path: "Sources/ClipCat",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
