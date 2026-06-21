// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NTSRadio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NTSRadio",
            path: "Sources/NTSRadio",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Keep the first pass on Swift 5 language mode to avoid
                // strict-concurrency churn; tighten later.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
