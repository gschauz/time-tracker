// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TimeTracker",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TimeTracker", targets: ["TimeTracker"])],
    targets: [
        .executableTarget(name: "TimeTracker"),
        .testTarget(name: "TimeTrackerTests", dependencies: ["TimeTracker"])
    ]
)
