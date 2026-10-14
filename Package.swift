// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "HueMenubar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HueMenubar", targets: ["HueMenubar"])],
    targets: [
        .executableTarget(name: "HueMenubar")
    ]
)
