// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NovaVoiceCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NovaVoiceCore", targets: ["NovaVoiceCore"]),
        .library(name: "NovaVoiceBridge", targets: ["NovaVoiceBridge"]),
        .executable(name: "novavoice-eval", targets: ["NovaVoiceEval"]),
    ],
    targets: [
        .target(name: "NovaVoiceBridge", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "NovaVoiceCore",
            dependencies: ["NovaVoiceBridge"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NovaVoiceEval",
            dependencies: ["NovaVoiceCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NovaVoiceCoreTests",
            dependencies: ["NovaVoiceCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
