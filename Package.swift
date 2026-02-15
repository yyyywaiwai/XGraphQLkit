// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "XDirectGraphQLPoC",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "XDirectGraphQLPoC",
            targets: ["XDirectGraphQLPoC"]
        )
    ],
    targets: [
        .target(
            name: "XDirectGraphQLPoC"
        ),
        .testTarget(
            name: "XDirectGraphQLPoCTests",
            dependencies: ["XDirectGraphQLPoC"]
        )
    ],
    swiftLanguageModes: [.v6]
)
