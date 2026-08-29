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
    public static let claude = ProviderIdentity(id: "claude", name: "Claude Code", tintName: "orange")
    public static let codex = ProviderIdentity(id: "codex", name: "Codex", tintName: "indigo")

    public static let all = [claude, codex]
}
