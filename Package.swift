// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fishbots",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Fishbots",
            path: "Sources/Fishbots",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network"),
                .linkedFramework("Speech"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
