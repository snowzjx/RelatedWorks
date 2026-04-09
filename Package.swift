// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RelatedWorks",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "RelatedWorksCore",
            path: "Sources/RelatedWorksCore",
            resources: [.process("BlacklistedModels.plist")]
        ),
        .executableTarget(
            name: "RelatedWorksTUI",
            dependencies: ["RelatedWorksCore"],
            path: "Sources/RelatedWorksTUI",
            exclude: []
        ),
        .testTarget(
            name: "RelatedWorksTests",
            dependencies: ["RelatedWorksCore"],
            path: "Tests/RelatedWorksTests"
        ),
    ]
)
