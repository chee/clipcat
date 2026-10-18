// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipcat",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clipcat",
            path: "Sources/Clipcat",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
