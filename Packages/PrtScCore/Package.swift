// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "PrtScCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PrtScCore", targets: ["PrtScCore"]),
    ],
    targets: [
        .target(
            name: "PrtScCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PrtScCoreTests",
            dependencies: ["PrtScCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
