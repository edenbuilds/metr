import Foundation
import Security

/// Read-only provider quota probes. Credentials remain in the stores written
/// by the providers; metr never refreshes, mutates, or uploads them elsewhere.
enum ProviderQuotaClient {
    private static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetchCodex(home: URL, now: Date) async -> ProviderSnapshot? {
        guard let token = codexAccessToken(home: home) else { return nil }
        var request = URLRequest(url: codexUsageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return failure(identity: KnownProvider.codex, reason: "Codex returned an invalid response.", now: now)
            }
            if http.statusCode == 401 {
                return authFailure(identity: KnownProvider.codex, now: now, source: "Codex usage API. Run `codex login` to refresh access.")
            }
            guard http.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rateLimit = object["rate_limit"] as? [String: Any],
                  let window = selectCodexWindow(rateLimit)
            else {
                return failure(identity: KnownProvider.codex, reason: "Codex usage API returned HTTP \(http.statusCode).", now: now)
            }
            return snapshot(
                identity: KnownProvider.codex,
                plan: object["plan_type"] as? String,
                reading: window,
                periods: codexWindows(rateLimit),
                now: now,
                source: "Provider-reported quota from chatgpt.com/backend-api/wham/usage."
            )
        } catch {
            return failure(identity: KnownProvider.codex, reason: "Codex usage refresh failed: \(error.localizedDescription)", now: now)
        }
    }

    static func fetchClaude(home: URL, now: Date) async -> ProviderSnapshot? {
        // Claude Code's statusLine payload is the strongest source available:
        // it is produced by the signed-in client itself and includes official
        // rate_limits without requiring metr to handle an OAuth credential.
        if let official = officialClaudeStatusline(home: home, now: now) {
            return official
        }
        let credentials = await Task.detached(priority: .utility) { claudeCredentials(home: home) }.value
        guard let credentials else { return nil }
        var request = URLRequest(url: claudeUsageURL)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/2.1.121", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return failure(identity: KnownProvider.claude, reason: "Claude returned an invalid response.", now: now)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return authFailure(identity: KnownProvider.claude, now: now, source: "Claude usage API. Run `claude /login` to refresh access.")
            }
            if http.statusCode == 429 {
                return failure(identity: KnownProvider.claude, reason: "Claude usage is temporarily rate limited.", now: now)
            }
            guard http.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reading = parseClaudeWindow(object["five_hour"], label: "5-hour window", span: 5 * 3600)
                    ?? parseClaudeWindow(object["seven_day"], label: "7-day window", span: 7 * 86_400)
            else {
                return failure(identity: KnownProvider.claude, reason: "Claude usage API returned HTTP \(http.statusCode).", now: now)
            }
            return snapshot(
                identity: KnownProvider.claude,
                plan: credentials.plan,
                reading: reading,
                periods: claudeWindows(object),
                now: now,
                source: "Provider-reported quota from api.anthropic.com/api/oauth/usage."
            )
        } catch {
            return failure(identity: KnownProvider.claude, reason: "Claude usage refresh failed: \(error.localizedDescription)", now: now)
        }
    }

    struct WindowReading: Equatable {
        let fraction: Double
        let resetAt: Date?
        let span: TimeInterval?
        let label: String
    }

    static func selectCodexWindow(_ rateLimit: [String: Any]) -> WindowReading? {
        codexWindows(rateLimit).first
    }

    static func codexWindows(_ rateLimit: [String: Any]) -> [WindowReading] {
        ["primary_window", "secondary_window"].compactMap { key -> WindowReading? in
            guard let value = rateLimit[key] as? [String: Any] else { return nil }
            return parseCodexWindow(value)
        }
        // Prefer the shortest reported window because it is the immediate
        // interruption risk; single-window weekly plans still work.
        .sorted { ($0.span ?? .greatestFiniteMagnitude) < ($1.span ?? .greatestFiniteMagnitude) }
    }

    static func parseCodexWindow(_ object: [String: Any]) -> WindowReading? {
        guard let raw = number(object["used_percent"]) else { return nil }
        let span = number(object["limit_window_seconds"])
        let reset = number(object["reset_at"]).map(Date.init(timeIntervalSince1970:))
        return WindowReading(
            fraction: min(1, max(0, raw / 100)),
            resetAt: reset,
            span: span,
            label: span.map(windowLabel) ?? "current window"
        )
    }

    static func parseClaudeWindow(
        _ value: Any?,
        label: String = "5-hour window",
        span: TimeInterval = 5 * 3600
    ) -> WindowReading? {
        guard let object = value as? [String: Any],
              let raw = number(object["utilization"] ?? object["used_percent"] ?? object["used_percentage"]) else { return nil }
        let reset: Date? = {
            if let seconds = number(object["resets_at"]) { return Date(timeIntervalSince1970: seconds) }
            guard let string = object["resets_at"] as? String else { return nil }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
        }()
        return WindowReading(
            fraction: min(1, max(0, raw / 100)),
            resetAt: reset,
            span: span,
            label: label
        )
    }

    static func claudeWindows(_ object: [String: Any]) -> [WindowReading] {
        [
            parseClaudeWindow(object["five_hour"], label: "5-hour window", span: 5 * 3600),
            parseClaudeWindow(object["seven_day"], label: "7-day window", span: 7 * 86_400)
        ].compactMap { $0 }
    }

    private static func officialClaudeStatusline(home: URL, now: Date) -> ProviderSnapshot? {
        let url = home.appendingPathComponent(".metr/statusline/latest.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let captured = number(object["captured_at_epoch"]),
              now.timeIntervalSince1970 - captured <= 600,
              let limits = object["rate_limits"] as? [String: Any] else { return nil }

        let periods = [
            parseClaudeWindow(limits["five_hour"], label: "5-hour window", span: 5 * 3600),
            parseClaudeWindow(limits["seven_day"], label: "7-day window", span: 7 * 86_400)
        ].compactMap { $0 }
        guard let reading = periods.first else { return nil }
        return snapshot(
            identity: KnownProvider.claude,
            plan: object["model"] as? String,
            reading: reading,
            periods: periods,
            now: now,
            source: "Official Claude Code statusLine rate_limits."
        )
    }

    private static func snapshot(
        identity: ProviderIdentity,
        plan: String?,
        reading: WindowReading,
        periods: [WindowReading],
        now: Date,
        source: String
    ) -> ProviderSnapshot {
        let hours = max(1, Int(round((reading.span ?? 5 * 3600) / 3600)))
        let start = reading.resetAt.map { $0.addingTimeInterval(-(reading.span ?? TimeInterval(hours * 3600))) }
        return ProviderSnapshot(
            identity: identity,
            model: plan,
            state: .live(fetched: now),
            usedFraction: reading.fraction,
            usedLabel: reading.label,
            window: UsageWindow(cadence: .rolling(hours: hours), windowStart: start, timeZone: TimeZone(identifier: "UTC") ?? .current),
            confidence: .measured,
            sourceDescription: source,
            quotaPeriods: periods.map {
                QuotaPeriod(label: $0.label, usedFraction: $0.fraction, resetAt: $0.resetAt, span: $0.span)
            }
        )
    }

    private static func authFailure(identity: ProviderIdentity, now: Date, source: String) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: identity,
            state: .authenticationRequired,
            window: UsageWindow(cadence: .rolling(hours: 5), timeZone: .autoupdatingCurrent),
            confidence: .measured,
            sourceDescription: source
        )
    }

    private static func failure(identity: ProviderIdentity, reason: String, now: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: identity,
            state: .unavailable(reason: reason),
            window: UsageWindow(cadence: .rolling(hours: 5), timeZone: .autoupdatingCurrent),
            confidence: .measured,
            sourceDescription: reason
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func windowLabel(_ seconds: Double) -> String {
        if seconds >= 6 * 86_400 { return "7-day window" }
        if seconds >= 86_400 { return "\(Int(round(seconds / 86_400)))-day window" }
        return "\(Int(round(seconds / 3600)))-hour window"
    }

    private static func codexAccessToken(home: URL) -> String? {
        let url = home.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    private struct ClaudeCredential {
        let token: String
        let plan: String?
    }

    private static func claudeCredentials(home: URL) -> ClaudeCredential? {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"], !env.isEmpty {
            return ClaudeCredential(token: env, plan: nil)
        }
        let isDefaultHome = home.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let keychain = isDefaultHome ? claudeKeychainBlobs() : []
        for blob in keychain + claudeFileBlobs(home: home) {
            guard let oauth = blob["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String, !token.isEmpty else { continue }
            return ClaudeCredential(token: token, plan: oauth["subscriptionType"] as? String)
        }
        return nil
    }

    private static func claudeFileBlobs(home: URL) -> [[String: Any]] {
        let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map(URL.init(fileURLWithPath:))
        let root = configured ?? home.appendingPathComponent(".claude", isDirectory: true)
        guard let data = FileManager.default.contents(atPath: root.appendingPathComponent(".credentials.json").path),
              let object = decodeSecret(data) else { return [] }
        return [object]
    }

    private static func claudeKeychainBlobs() -> [[String: Any]] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let service = item[kSecAttrService as String] as? String,
                  service == "Claude Code-credentials" || service.hasPrefix("Claude Code-credentials-"),
                  let account = item[kSecAttrAccount as String] as? String else { return nil }
            return readSecret(service: service, account: account)
        }
    }

    /// `security` is in Claude Code's keychain ACL and remains prompt-free
    /// across token rotations. The app never writes the credential item.
    private static func readSecret(service: String, account: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return decodeSecret(data)
        } catch {
            return nil
        }
    }

    private static func decodeSecret(_ data: Data) -> [String: Any]? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return object }
        guard let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw.count.isMultiple(of: 2), raw.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = Data(capacity: raw.count / 2)
        var index = raw.startIndex
        while index < raw.endIndex {
            let next = raw.index(index, offsetBy: 2)
            guard let byte = UInt8(raw[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    }
}
