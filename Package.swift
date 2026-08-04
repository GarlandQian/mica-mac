// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Mica",
    defaultLocalization: "en",
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .executable(name: "Mica", targets: ["Mica"]),
        .library(name: "MicaCore", targets: ["MicaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", exact: "2.4.2"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", exact: "2.9.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", exact: "2.4.1"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.0"),
    ],
    targets: [
        .target(
            name: "MicaCore",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2TransportServices", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            exclude: ["Protocols/SingBox/started_service.proto"]
        ),
        .executableTarget(
            name: "Mica",
            dependencies: ["MicaCore"],
            exclude: ["App/Info.plist"],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Mica/App/Info.plist",
                ]),
            ]
        ),
        .testTarget(
            name: "MicaCoreTests",
            dependencies: [
                "MicaCore",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCInProcessTransport", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MicaTests",
            dependencies: ["Mica", "MicaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
