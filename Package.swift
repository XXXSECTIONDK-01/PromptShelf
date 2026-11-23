// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PromptShelf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PromptShelf", targets: ["PromptShelf"])],
    targets: [
        .target(name: "PromptCore"),
        .target(name: "PromptUI", dependencies: ["PromptCore"]),
        .executableTarget(name: "PromptShelf", dependencies: ["PromptCore", "PromptUI"]),
        .executableTarget(name: "MarkdownUIProbe", dependencies: ["PromptCore", "PromptUI"], path: "Tests/MarkdownUIProbe"),
        .executableTarget(name: "InputProbe", path: "Tests/InputProbe"),
        .executableTarget(name: "NotesBridgeChecks", path: "Tests/NotesBridgeChecks", exclude: ["fixtures.js"]),
        .executableTarget(name: "PromptActionChecks", dependencies: ["PromptCore", "PromptUI"], path: "Tests/PromptActionChecks"),
        .executableTarget(name: "StorageChecks", dependencies: ["PromptCore"], path: "Tests/StorageChecks"),
        .executableTarget(name: "PromptCoreChecks", dependencies: ["PromptCore"], path: "Tests/PromptCoreTests")
    ]
)
