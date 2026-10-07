// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlogAssistant",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "BlogAssistant", targets: ["BlogAssistant"])],
    targets: [
        .executableTarget(name: "BlogAssistant")
    ]
)
