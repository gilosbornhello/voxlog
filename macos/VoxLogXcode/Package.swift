// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoxLog",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VoxLog",
            path: ".",
            exclude: ["Info.plist", "VoxLog.entitlements"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
