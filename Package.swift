// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapLens",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "SnapLens", path: "Sources/SnapLens", exclude: ["Resources"])
    ]
)
