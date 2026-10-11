// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Onyx",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Onyx", targets: ["Onyx"]),
    ],
    dependencies: [
        .package(path: "Vendor/SwiftTerm"),
    ],
    targets: [
        .target(name: "OnyxCore"),
        .executableTarget(
            name: "Onyx",
            dependencies: ["OnyxCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        .testTarget(name: "OnyxCoreTests", dependencies: ["OnyxCore"]),
    ]
)
