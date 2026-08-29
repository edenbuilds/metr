import Foundation

/// Why a fetch could not produce usable numbers.
public enum UsageDataError: Error, Equatable, Sendable {
    case offline
    case authenticationRequired(provider: String)
    case unavailable(reason: String)
}

/// The seam between "where numbers come from" and "how they are drawn".
///
/// Adding a real provider adapter means conforming to this and nothing else —
/// no view in the app knows which adapter is in use.
public protocol UsageDataSource: AnyObject {
    var kind: DataSourceKind { get }
    /// A sentence describing exactly what this adapter reads, shown in preferences.
    var provenance: String { get }
    func fetch(now: Date) async -> UsageSnapshot
}

// MARK: - Known providers

public enum KnownProvider {
    public static let claude = ProviderIdentity(id: "claude", name: "Claude", tintName: "orange")
    public static let codex = ProviderIdentity(id: "codex", name: "Codex", tintName: "indigo")

    public static let all = [claude, codex]
}

/// Popular AI apps available as explicit opt-ins in Settings. Unsupported
/// quotas remain unavailable rather than being inferred from local telemetry.
public struct SupportedApp: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let tintName: String

    public init(id: String, name: String, tintName: String) {
        self.id = id
        self.name = name
        self.tintName = tintName
    }

    public var identity: ProviderIdentity { ProviderIdentity(id: id, name: name, tintName: tintName) }
}

public enum AppCatalog {
    public static let all: [SupportedApp] = [
        SupportedApp(id: "cursor", name: "Cursor", tintName: "mint"),
        SupportedApp(id: "gemini", name: "Gemini", tintName: "blue"),
        SupportedApp(id: "github-copilot", name: "GitHub Copilot", tintName: "purple"),
        SupportedApp(id: "perplexity", name: "Perplexity", tintName: "indigo"),
        SupportedApp(id: "windsurf", name: "Windsurf", tintName: "mint"),
        SupportedApp(id: "cline", name: "Cline", tintName: "orange"),
        SupportedApp(id: "continue", name: "Continue", tintName: "blue"),
        SupportedApp(id: "opencode", name: "OpenCode", tintName: "purple"),
        SupportedApp(id: "amazon-q", name: "Amazon Q", tintName: "orange"),
        SupportedApp(id: "openai-chatgpt", name: "ChatGPT", tintName: "green")
    ]
}
