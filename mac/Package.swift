// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NTSRadio",
    // grpc-swift v2 (used for the Firestore live-tracks listener) requires
    // macOS 15+. That sets the app's floor.
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.9.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.4.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.4"),
    ],
    targets: [
        // Pure Ratcliff/Obershelp string matching + NTS date-alias vocabulary,
        // with zero I/O — so the accuracy probe can link it without pulling in
        // the app's Cache/NTSAPI/MainActor machinery.
        .target(
            name: "EpisodeMatch",
            path: "Sources/EpisodeMatch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Firestore Listen client + generated protobuf/gRPC code, isolated from
        // the app so a probe tool can share it.
        .target(
            name: "NTSFirestore",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/NTSFirestore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NTSRadio",
            dependencies: [
                "NTSFirestore",
                "EpisodeMatch",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/NTSRadio",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Keep the first pass on Swift 5 language mode to avoid
                // strict-concurrency churn; tighten later.
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // SwiftPM's default rpath for an executable is @loader_path —
                // the binary's own directory — which only matches the flat
                // .build/release layout it links against, not a real .app
                // bundle. `make app` puts Sparkle.framework in the standard
                // Contents/Frameworks/, so the binary needs the standard
                // rpath that finds it there too.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // Throwaway: prove the Firestore Listen stream end-to-end with a real
        // token. `NTS_TOKEN=<idToken> swift run FSProbe <mixtape-alias>`.
        // `swift run FSProbe accuracy` instead runs the episode-index-resolver
        // accuracy harness against the live sitemap.
        .executableTarget(
            name: "FSProbe",
            dependencies: ["NTSFirestore", "EpisodeMatch"],
            path: "Sources/FSProbe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
