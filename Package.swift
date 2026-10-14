// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Glowdesk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Glowdesk", targets: ["Glowdesk"])],
    targets: [
        .executableTarget(name: "Glowdesk")
    ]
)
