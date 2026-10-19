// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "eqpop",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "eqpop", path: "Sources/eqpop")]
)
