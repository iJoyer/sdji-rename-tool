// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SDJIRenameTool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SDJI Rename Tool", targets: ["SDJIRenameTool"])
    ],
    targets: [
        .executableTarget(
            name: "SDJIRenameTool",
            resources: [.process("Resources")]
        )
    ]
)
