// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "LyricsKit",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "LyricsKit",
            targets: ["LyricsKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/ddddxxx/Regex", from: "1.0.1"),
        .package(url: "https://github.com/MxIris-Library-Forks/SwiftCF", from: "0.2.2"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/attaswift/BigInt", from: "5.6.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.9.0"),
        .package(url: "https://github.com/Mx-Iris/FrameworkToolbox", from: "0.5.4"),
    ],
    targets: [
        .target(
            name: "LyricsKit",
            dependencies: [
                "LyricsCore",
                "LyricsService",
                "LyricsServiceUI",
            ]
        ),
        .target(
            name: "LyricsCore",
            dependencies: [
                .product(name: "Regex", package: "Regex"),
                .product(name: "SwiftCF", package: "SwiftCF"),
            ]
        ),
        .target(
            name: "LyricsService",
            dependencies: [
                "LyricsCore",
                .product(name: "Regex", package: "Regex"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "FoundationToolbox", package: "FrameworkToolbox"),
            ]
        ),
        .target(
            name: "LyricsServiceUI",
            dependencies: [
                "LyricsCore",
                "LyricsService",
            ]
        ),
        .testTarget(
            name: "LyricsKitTests",
            dependencies: [
                "LyricsCore",
                "LyricsService",
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
