// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Onyx",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Onyx", targets: ["Onyx"]),
        .executable(name: "onyx-pane", targets: ["onyx-pane"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.11.2"),
    ],
    targets: [
        .target(name: "OnyxCore"),
        .executableTarget(
            name: "Onyx",
            dependencies: ["OnyxCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .executableTarget(name: "onyx-pane", dependencies: ["OnyxCore"]),
        .testTarget(name: "OnyxCoreTests", dependencies: ["OnyxCore"]),
    ]
)
