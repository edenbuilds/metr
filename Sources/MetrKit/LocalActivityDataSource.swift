import Foundation

/// Reads agent activity that already exists on this Mac.
///
/// What this adapter is and is not:
/// Local activity is always read first. When the provider's existing login is
/// available, metr replaces the quota proxy with provider-reported usage from
/// the provider's own endpoint. Credentials remain read-only and local.
public final class LocalActivityDataSource: UsageDataSource {

    public let kind: DataSourceKind = .local

    public var provenance: String {
        "Reads local Codex/Claude session files. Quota prefers Claude Code's official statusLine rate_limits, then read-only provider endpoints, then an explicitly estimated local proxy."
    }

    /// Assumption used for the cost estimate, surfaced verbatim in the UI.
    public struct CostModel: Sendable {
        public var tokensPerMessage: Double
        public var dollarsPerMillionTokens: Double

        public init(tokensPerMessage: Double = 1_400, dollarsPerMillionTokens: Double = 6) {
            self.tokensPerMessage = tokensPerMessage
            self.dollarsPerMillionTokens = dollarsPerMillionTokens
        }

        public var assumption: String {
            "Assumes ~\(Int(tokensPerMessage)) tokens per message at $\(Int(dollarsPerMillionTokens))/M blended. Not billing data."
        }

        public func estimate(messages: Int) -> Double {
            Double(messages) * tokensPerMessage / 1_000_000 * dollarsPerMillionTokens
        }
    }

    private let home: URL
    private let fileManager: FileManager
    private let costModel: CostModel
    /// Cap on how many project directories we stat per refresh, so a machine
    /// with hundreds of projects does not turn a refresh into a disk sweep.
    private let projectDirectoryLimit: Int

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        costModel: CostModel = CostModel(),
        projectDirectoryLimit: Int = 8
    ) {
        self.home = home
        self.fileManager = fileManager
        self.costModel = costModel
        self.projectDirectoryLimit = projectDirectoryLimit
    }

    public func fetch(now: Date) async -> UsageSnapshot {
        let codexSessions = readCodexSessions()
        let claudeSessions = readClaudeSessions()
        let activity = readClaudeActivity()
            + dailySessionActivity(codexSessions, providerID: KnownProvider.codex.id)
        let sessions = (codexSessions + claudeSessions).sorted { $0.lastActive > $1.lastActive }

        var providers: [ProviderSnapshot] = []
        providers.append(snapshot(
            identity: KnownProvider.claude,
            sessions: claudeSessions,
            activity: activity,
            now: now,
            missingReason: "No session files found under ~/.claude/projects."
        ))
        providers.append(snapshot(
            identity: KnownProvider.codex,
            sessions: codexSessions,
            activity: [],
            now: now,
            missingReason: "No ~/.codex/session_index.jsonl on this Mac."
        ))

        async let codexQuota = ProviderQuotaClient.fetchCodex(home: home, now: now)
        async let claudeQuota = ProviderQuotaClient.fetchClaude(home: home, now: now)
        let (reportedClaude, reportedCodex) = await (claudeQuota, codexQuota)
        let official = [reportedClaude, reportedCodex].compactMap { $0 }
        providers = providers.map { local in
            guard let reported = official.first(where: { $0.id == local.id }) else { return local }
            guard reported.usedFraction != nil || local.usedFraction == nil else {
                var fallback = local
                fallback.sourceDescription += " Official quota unavailable: \(reported.state.label)."
                return fallback
            }
            var merged = reported
            merged.estimatedCost = local.estimatedCost
            merged.costAssumption = local.costAssumption
            merged.contextUsed = local.contextUsed
            merged.contextBudget = local.contextBudget
            return merged
        }

        return UsageSnapshot(
            providers: providers,
            sessions: Array(sessions.prefix(12)),
            activity: activity,
            capturedAt: now
        )
    }

    // MARK: - Provider synthesis

    /// Codex's index exposes trustworthy session timestamps, but not message or
    /// token totals. Record only what the source actually knows.
    private func dailySessionActivity(_ sessions: [SessionRecord], providerID: String) -> [DailyActivity] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.lastActive) }
        return grouped.map { day, records in
            DailyActivity(
                date: day,
                messageCount: 0,
                sessionCount: records.count,
                toolCallCount: 0,
                providerID: providerID
            )
        }.sorted { $0.date < $1.date }
    }

    private func snapshot(
        identity: ProviderIdentity,
        sessions: [SessionRecord],
        activity: [DailyActivity],
        now: Date,
        missingReason: String
    ) -> ProviderSnapshot {
        let windowHours = 5
        let windowLength = TimeInterval(windowHours) * 3600

        guard !sessions.isEmpty else {
            return ProviderSnapshot(
                identity: identity,
                model: nil,
                state: .unavailable(reason: missingReason),
                window: UsageWindow(cadence: .rolling(hours: windowHours), timeZone: .current),
                confidence: .measured,
                sourceDescription: provenance
            )
        }

        // The current window opens at the earliest session activity within the
        // last `windowHours`; if nothing is that recent, there is no open window.
        let cutoff = now.addingTimeInterval(-windowLength)
        let inWindow = sessions.filter { $0.lastActive >= cutoff }
        let windowStart = inWindow.map(\.lastActive).min()

        // Proxy load: sessions touched in this window against the busiest
        // equivalent window over the last week. Explicitly *not* a plan limit.
        let peak = peakWindowCount(sessions: sessions, windowLength: windowLength, now: now)
        let fraction: Double? = peak > 0 ? min(1, Double(inWindow.count) / Double(peak)) : nil

        // Cost from measured message counts for today, under a stated assumption.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let todayMessages = activity.first { cal.isDate($0.date, inSameDayAs: now) }?.messageCount
        let cost = todayMessages.map { costModel.estimate(messages: $0) }

        // Freshness is judged from the most recent thing we actually saw.
        let newest = sessions.map(\.lastActive).max() ?? now
        let age = now.timeIntervalSince(newest)
        let state: DataState = age > 6 * 3600 ? .stale(fetched: newest, age: age) : .live(fetched: now)

        return ProviderSnapshot(
            identity: identity,
            model: nil,
            state: state,
            usedFraction: fraction,
            usedLabel: fraction == nil ? nil : "of your busiest \(windowHours)h",
            window: UsageWindow(cadence: .rolling(hours: windowHours), windowStart: windowStart, timeZone: .current),
            contextUsed: nil,
            contextBudget: nil,
            estimatedCost: cost,
            costAssumption: cost == nil ? nil : costModel.assumption,
            confidence: .estimated,
            sourceDescription: "Local session files. Load is measured against your own busiest window, not a plan limit."
        )
    }

    /// Highest number of sessions active in any `windowLength` slice of the last week.
    private func peakWindowCount(sessions: [SessionRecord], windowLength: TimeInterval, now: Date) -> Int {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let times = sessions.map(\.lastActive).filter { $0 >= weekAgo }.sorted()
        guard !times.isEmpty else { return 0 }
        var best = 0
        var start = 0
        for end in times.indices {
            while times[end].timeIntervalSince(times[start]) > windowLength { start += 1 }
            best = max(best, end - start + 1)
        }
        return best
    }

    // MARK: - Codex

    /// `~/.codex/session_index.jsonl`: one small JSON object per line.
    private func readCodexSessions() -> [SessionRecord] {
        let url = home.appendingPathComponent(".codex/session_index.jsonl")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8) else { return [] }

        struct Row: Decodable {
            let id: String
            let thread_name: String?
            let updated_at: String
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        var records: [SessionRecord] = []
        // Only the tail matters; the index is append-ordered by recency.
        for line in text.split(separator: "\n").suffix(80) {
            guard let row = try? decoder.decode(Row.self, from: Data(line.utf8)) else { continue }
            guard let date = iso.date(from: row.updated_at) ?? isoPlain.date(from: row.updated_at) else { continue }
            records.append(SessionRecord(
                id: "codex-\(row.id)",
                title: row.thread_name?.isEmpty == false ? row.thread_name! : "Untitled session",
                providerID: KnownProvider.codex.id,
                lastActive: date,
                workingDirectory: nil
            ))
        }
        return records
    }

    // MARK: - Claude Code

    /// Session transcripts live at `~/.claude/projects/<slug>/<uuid>.jsonl`.
    /// Only timestamps are read — never the transcript contents, which are both
    /// large and private.
    private func readClaudeSessions() -> [SessionRecord] {
        let root = home.appendingPathComponent(".claude/projects")
        guard let projectDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Stat the directories first and only descend into the most recent few.
        let recentDirs = projectDirs
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                      values.isDirectory == true,
                      let modified = values.contentModificationDate else { return nil }
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(projectDirectoryLimit)

        var records: [SessionRecord] = []
        for (dir, _) in recentDirs {
            guard let files = try? fileManager.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let transcripts = files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (URL, Date)? in
                    guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
                    return (url, modified)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(4)

            for (file, modified) in transcripts {
                records.append(SessionRecord(
                    id: "claude-\(file.deletingPathExtension().lastPathComponent)",
                    title: Self.projectTitle(fromSlug: dir.lastPathComponent),
                    providerID: KnownProvider.claude.id,
                    lastActive: modified,
                    workingDirectory: Self.projectPath(fromSlug: dir.lastPathComponent)
                ))
            }
        }
        return records
    }

    /// "-Users-alex--projects-foo-bar" -> "foo bar".
    static func projectTitle(fromSlug slug: String) -> String {
        let path = projectPath(fromSlug: slug)
        let last = path.split(separator: "/").last.map(String.init) ?? slug
        return last.replacingOccurrences(of: "-", with: " ")
    }

    /// Claude Code encodes a path by replacing "/" with "-". The mapping is
    /// lossy (a real "-" in a folder name is indistinguishable), so this is a
    /// best-effort label, never used to open or write anything.
    static func projectPath(fromSlug slug: String) -> String {
        guard slug.hasPrefix("-") else { return slug }
        return "/" + slug.dropFirst().replacingOccurrences(of: "-", with: "/")
    }

    // MARK: - Activity

    /// `~/.claude/stats-cache.json` holds real per-day counts. It is written
    /// periodically, so it can legitimately be days behind — which is exactly
    /// the case the "stale" state exists to communicate.
    private func readClaudeActivity() -> [DailyActivity] {
        let url = home.appendingPathComponent(".claude/stats-cache.json")
        guard let data = try? Data(contentsOf: url) else { return [] }

        struct Cache: Decodable {
            struct Day: Decodable {
                let date: String
                let messageCount: Int
                let sessionCount: Int
                let toolCallCount: Int
            }
            let dailyActivity: [Day]
        }
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return [] }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"

        return cache.dailyActivity.compactMap { day in
            guard let date = parser.date(from: day.date) else { return nil }
            return DailyActivity(
                date: date,
                messageCount: day.messageCount,
                sessionCount: day.sessionCount,
                toolCallCount: day.toolCallCount,
                providerID: KnownProvider.claude.id
            )
        }
        .sorted { $0.date < $1.date }
    }
}
