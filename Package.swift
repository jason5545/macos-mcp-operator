// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "macos-mcp-operator",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "macos-mcp-operator",
            targets: ["macos-mcp-operator"]
        ),
        .executable(
            name: "macos-mcp-operator-host",
            targets: ["macos-mcp-operator-host"]
        ),
    ],
    targets: [
        .target(
            name: "CoreTypes"
        ),
        .target(
            name: "ConfigStore",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "AuditLogger",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "SafetyEngine",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "AutomationCore",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "MacOSAdapters",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "MCPCore",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "BrokerCore",
            dependencies: ["CoreTypes"]
        ),
        .target(
            name: "OperatorCore",
            dependencies: [
                "CoreTypes",
                "MCPCore",
                "AutomationCore",
                "MacOSAdapters",
                "SafetyEngine",
                "ConfigStore",
                "AuditLogger",
                "BrokerCore",
            ]
        ),
        .executableTarget(
            name: "macos-mcp-operator",
            dependencies: ["OperatorCore"]
        ),
        .executableTarget(
            name: "macos-mcp-operator-host",
            dependencies: ["BrokerCore", "ConfigStore"]
        ),
        .testTarget(
            name: "MCPCoreTests",
            dependencies: ["MCPCore", "CoreTypes"]
        ),
        .testTarget(
            name: "SafetyEngineTests",
            dependencies: ["SafetyEngine", "CoreTypes"]
        ),
        .testTarget(
            name: "AutomationCoreTests",
            dependencies: ["AutomationCore", "CoreTypes"]
        ),
        .testTarget(
            name: "MacOSAdaptersTests",
            dependencies: ["MacOSAdapters", "CoreTypes"]
        ),
        .testTarget(
            name: "OperatorCoreTests",
            dependencies: ["OperatorCore", "CoreTypes", "MCPCore"]
        ),
        .testTarget(
            name: "BrokerCoreTests",
            dependencies: ["BrokerCore", "CoreTypes"]
        ),
    ]
)
