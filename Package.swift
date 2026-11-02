// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapLens",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "SnapLens", path: "Sources/SnapLens", exclude: ["Resources"]),
        // Testes da lógica que não depende de tela: `swift test` (roda no CI antes de gerar o DMG).
        .testTarget(name: "SnapLensTests", dependencies: ["SnapLens"], path: "Tests/SnapLensTests"),
    ]
)
