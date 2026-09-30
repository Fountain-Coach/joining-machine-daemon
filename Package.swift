// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "JoiningMachineDaemonPublic",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "JoiningMachineDaemon", targets: ["JoiningMachineDaemon"]),
        .executable(name: "joining-machine-daemon", targets: ["JoiningMachineDaemonExecutable"])
    ],
    dependencies: [
        .package(url: "https://github.com/Fountain-Coach/midi2.git",
                 revision: "08fe3d2a02d10e7737b0c533ece583b08397c67b")
    ],
    targets: [
        .target(
            name: "MIDI2CITransport",
            dependencies: [
                .product(name: "MIDI2", package: "midi2"),
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Sources/MIDI2CITransport"
        ),
        .target(
            name: "JoiningMachineDaemon",
            dependencies: ["MIDI2CITransport", .product(name: "MIDI2Transports", package: "midi2"),
                           .product(name: "MIDI2", package: "midi2")],
            path: "Sources/JoiningMachineDaemon"
        ),
        .executableTarget(
            name: "JoiningMachineDaemonExecutable",
            dependencies: ["JoiningMachineDaemon", .product(name: "MIDI2Transports", package: "midi2")],
            path: "Sources/JoiningMachineDaemonExecutable"
        ),
        .testTarget(
            name: "JoiningMachineDaemonTests",
            dependencies: ["JoiningMachineDaemon"]
        )
    ]
)
