// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NovaVoiceCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NovaVoiceCore", targets: ["NovaVoiceCore"]),
        .library(name: "NovaVoiceBridge", targets: ["NovaVoiceBridge"]),
        // Optional open models through MLX: the Mac app and the iPhone app (not its extensions).
        .library(name: "NovaVoiceLocalModel", targets: ["NovaVoiceLocalModel"]),
        .executable(name: "novavoice-eval", targets: ["NovaVoiceEval"]),
    ],
    dependencies: [
        // The FoundationModels bridge is left out: LahLah Voice calls the model directly.
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3"),
            traits: []),
        .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(name: "NovaVoiceBridge", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "NovaVoiceCore",
            dependencies: ["NovaVoiceBridge"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "NovaVoiceLocalModel",
            dependencies: [
                "NovaVoiceCore",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NovaVoiceEval",
            dependencies: ["NovaVoiceCore", "NovaVoiceLocalModel"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NovaVoiceCoreTests",
            dependencies: ["NovaVoiceCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
