// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XGraphQLkit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "XGraphQLkit",
            targets: ["XGraphQLkit"]
        )
    ],
    targets: [
        .target(
            name: "XGraphQLkit"
        ),
        .testTarget(
            name: "XGraphQLkitTests",
            dependencies: ["XGraphQLkit"]
        )
    ],
    swiftLanguageModes: [.v6]
)
