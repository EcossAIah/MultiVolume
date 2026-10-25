// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MultiVolume",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MultiVolume",
            path: "Sources/MultiVolume",
            swiftSettings: [
                // Swift 6 toolchain, Swift 5 language mode.
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "MultiVolumeTests",
            dependencies: ["MultiVolume"],
            path: "Tests/MultiVolumeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
