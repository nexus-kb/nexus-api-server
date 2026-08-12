// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "NexusKb",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        // 💧 A server-side Swift web framework.
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
        // Postgres client
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.1"),
        // Vapor Queues to build on top of Postgres
        .package(url: "https://github.com/vapor/queues.git", from: "1.18.0"),
    ],
    targets: [
        .executableTarget(
            name: "NexusKb",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Queues", package: "queues"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "NexusKbTests",
            dependencies: [
                .target(name: "NexusKb"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: swiftSettings
        )
    ]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
] }
