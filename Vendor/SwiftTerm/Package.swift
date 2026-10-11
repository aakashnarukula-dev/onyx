// swift-tools-version:6.0
// SwiftTerm v1.20.0 (MIT, github.com/migueldeicaza/SwiftTerm), vendored for Onyx.
// Local changes: the Metal shader is not compiled at build time (the Command Line Tools have
// no `metal` compiler; SwiftTerm's opt-in GPU renderer compiles it from source at runtime),
// and the build-info plugin is replaced by a static SwiftTermBuildInfo.swift.
import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v11)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md", "Apple/Metal/Shaders.metal"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
