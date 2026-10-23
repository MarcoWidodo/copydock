// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CopyDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CopyDock", targets: ["CopyDock"]),
        .executable(name: "CopyDockChecks", targets: ["CopyDockChecks"])
    ],
    targets: [
        .target(
            name: "CopyDockCore",
            path: "Sources/CopyDockCore"
        ),
        .executableTarget(
            name: "CopyDock",
            dependencies: ["CopyDockCore"],
            path: "Sources/CopyDock"
        ),
        .executableTarget(
            name: "CopyDockChecks",
            dependencies: ["CopyDockCore"],
            path: "Checks"
        )
    ],
    swiftLanguageModes: [.v5]
)
