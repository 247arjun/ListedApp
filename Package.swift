// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Listed",
    defaultLocalization: "en",
    platforms: [
        // Listed targets the Liquid Glass generation of Apple OSes.
        .macOS("26.0"),
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "ListedCore",
            targets: ["ListedCore"]
        ),
        .library(
            name: "ListedUI",
            targets: ["ListedUI"]
        )
    ],
    targets: [
        .target(
            name: "ListedCore",
            path: "Sources/ListedCore"
        ),
        .target(
            name: "ListedUI",
            dependencies: ["ListedCore"],
            path: "Sources/ListedUI"
        ),
        .testTarget(
            name: "ListedCoreTests",
            dependencies: ["ListedCore"],
            path: "Tests/ListedCoreTests"
        )
    ]
)
