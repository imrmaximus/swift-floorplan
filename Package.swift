// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-floorplan",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "swift-floorplan", targets: ["swift-floorplan"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "FloorplanScanner",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .executableTarget(name: "swift-floorplan", dependencies: ["FloorplanScanner"]),
        .testTarget(name: "FloorplanScannerTests", dependencies: ["FloorplanScanner"]),
    ]
)
