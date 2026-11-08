// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AoE2MacTrainer",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AoE2MacTrainer", targets: ["AoE2MacTrainer"])
    ],
    targets: [
        .executableTarget(
            name: "AoE2MacTrainer",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AoE2MacTrainerTests",
            dependencies: ["AoE2MacTrainer"]
        )
    ]
)
