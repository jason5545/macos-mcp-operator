import Foundation

public enum MCPVersioning {
    public static let supported: [String] = [
        "2025-11-25",
        "2025-06-18",
        "2025-03-26",
    ]

    public static var latest: String {
        supported[0]
    }

    public static func negotiate(clientRequestedVersion: String) -> String {
        if supported.contains(clientRequestedVersion) {
            return clientRequestedVersion
        }
        return latest
    }
}
