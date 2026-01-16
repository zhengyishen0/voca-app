// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voca",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Voca",
            path: "Voca",
            resources: [.copy("Resources")],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "Frameworks"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "Frameworks",
                    "-framework", "VoicePipeline",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        )
    ]
)
