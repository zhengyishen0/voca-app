// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voca",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "VocaLib", targets: ["VocaLib"])
    ],
    targets: [
        .binaryTarget(
            name: "VoicePipeline",
            path: "Frameworks/VoicePipeline.xcframework"
        ),
        .target(
            name: "VocaLib",
            dependencies: ["VoicePipeline"],
            path: "Voca",
            resources: [.copy("Resources")]
        )
    ]
)
