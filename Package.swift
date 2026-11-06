// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DroidMirror",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DroidMirror",
            targets: ["DroidMirrorApp"]
        ),
        .executable(
            name: "TestRunner",
            targets: ["TestRunner"]
        ),
        .executable(
            name: "PhoneSimulator1000",
            targets: ["PhoneSimulator1000"]
        ),
        .library(
            name: "DroidMirrorCore",
            targets: ["DroidMirrorCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DroidMirrorCore",
            dependencies: [],
            path: "Sources/DroidMirrorCore"
        ),
        .executableTarget(
            name: "DroidMirrorApp",
            dependencies: ["DroidMirrorCore"],
            path: "Sources/DroidMirrorApp"
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["DroidMirrorCore"],
            path: "Tests/TestRunner"
        ),
        .executableTarget(
            name: "PhoneSimulator1000",
            dependencies: ["DroidMirrorCore"],
            path: "Tests/PhoneSimulator1000"
        )
    ]
)
