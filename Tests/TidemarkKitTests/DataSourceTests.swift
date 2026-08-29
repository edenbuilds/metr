import XCTest
@testable import TidemarkKit

final class DataSourceTests: XCTestCase {

    // MARK: Mock

    func testMockIsDeterministicForTheSameInstant() async {
        let now = Fixture.date(2026, 8, 30, 12, 0)
        let source = MockUsageDataSource(scenario: .healthy)
        let a = await source.fetch(now: now)
        let b = await source.fetch(now: now)
        XCTAssertEqual(a, b, "Screenshots and tests need a stable picture")
    }

    func testEveryMockScenarioProducesACoherentSnapshot() async {
        let now = Fixture.date(2026, 8, 30, 12, 0)
        for scenario in MockUsageDataSource.Scenario.allCases {
            let snapshot = await MockUsageDataSource(scenario: scenario).fetch(now: now)
            for provider in snapshot.providers {
                if provider.state.hasNoData {
                    XCTAssertNil(provider.usedFraction, "\(scenario): a state with no data must not carry a number")
                } else if let fraction = provider.usedFraction {
                    XCTAssertTrue((0...1).contains(fraction), "\(scenario): \(fraction) out of range")
                }
            }
        }
    }

    func testNoDataScenarioIsCompletelyEmpty() async {
        let snapshot = await MockUsageDataSource(scenario: .noData).fetch(now: Date())
        XCTAssertTrue(snapshot.providers.isEmpty)
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertTrue(snapshot.activity.isEmpty)
    }

    func testMixedScenarioCoversBothAHealthyAndAnUnavailableProvider() async {
        let snapshot = await MockUsageDataSource(scenario: .mixed).fetch(now: Date())
        XCTAssertTrue(snapshot.providers.contains { $0.state.isTrustworthy })
        XCTAssertTrue(snapshot.providers.contains { $0.state == .authenticationRequired })
    }

    func testOfflineScenarioDistinguishesCachedFromNothing() async {
        let snapshot = await MockUsageDataSource(scenario: .offline).fetch(now: Date())
        XCTAssertTrue(snapshot.providers.contains { !$0.state.hasNoData }, "One provider has a cached number")
        XCTAssertTrue(snapshot.providers.contains { $0.state.hasNoData }, "One has nothing at all")
    }

    // MARK: Local adapter — path decoding

    func testProjectSlugDecodesToAPathAndTitle() {
        XCTAssertEqual(
            LocalActivityDataSource.projectPath(fromSlug: "-Users-omkar-shb-case-manager"),
            "/Users/omkar/shb/case/manager"
        )
        XCTAssertEqual(
            LocalActivityDataSource.projectTitle(fromSlug: "-Users-omkar-overwater"),
            "overwater"
        )
    }

    func testSlugWithoutLeadingSeparatorIsLeftAlone() {
        XCTAssertEqual(LocalActivityDataSource.projectPath(fromSlug: "plain"), "plain")
    }

    // MARK: Local adapter — reading a fixture home

    /// Builds a throwaway home directory with the same shape as the real one, so
    /// the adapter is exercised end to end without touching the user's files.
    private func makeFixtureHome() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tidemark-tests-\(UUID().uuidString)")
        let fm = FileManager.default

        let codex = root.appendingPathComponent(".codex")
        try fm.createDirectory(at: codex, withIntermediateDirectories: true)
        let index = """
        {"id":"aaa","thread_name":"Build the panel","updated_at":"2026-08-29T12:23:55.285089Z"}
        {"id":"bbb","thread_name":"Fix reset math","updated_at":"2026-08-29T18:45:48.186535Z"}
        {"id":"ccc","thread_name":"","updated_at":"2026-08-29T19:00:00Z"}
        not json at all
        """
        try index.write(to: codex.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

        let project = root.appendingPathComponent(".claude/projects/-Users-tester-demo")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try "{}".write(to: project.appendingPathComponent("session-one.jsonl"), atomically: true, encoding: .utf8)

        let stats = """
        {"version":4,"lastComputedDate":"2026-08-29","dailyActivity":[
          {"date":"2026-08-27","messageCount":100,"sessionCount":2,"toolCallCount":30},
          {"date":"2026-08-28","messageCount":250,"sessionCount":4,"toolCallCount":80}
        ]}
        """
        try stats.write(to: root.appendingPathComponent(".claude/stats-cache.json"), atomically: true, encoding: .utf8)
        return root
    }

    func testLocalAdapterReadsSessionsAndActivityFromDisk() async throws {
        let home = try makeFixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let snapshot = await LocalActivityDataSource(home: home).fetch(now: Date())

        XCTAssertTrue(snapshot.sessions.contains { $0.title == "Build the panel" })
        XCTAssertTrue(snapshot.sessions.contains { $0.title == "Untitled session" }, "A blank thread name still needs a label")
        XCTAssertTrue(snapshot.sessions.contains { $0.providerID == KnownProvider.claude.id })
        XCTAssertEqual(snapshot.activity.count, 2)
        XCTAssertEqual(snapshot.activity.first?.messageCount, 100)
        XCTAssertEqual(snapshot.activity.last?.messageCount, 250, "Activity must come back in date order")
    }

    func testLocalAdapterSurvivesAMalformedIndexLine() async throws {
        let home = try makeFixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let snapshot = await LocalActivityDataSource(home: home).fetch(now: Date())
        XCTAssertEqual(snapshot.sessions.filter { $0.providerID == KnownProvider.codex.id }.count, 3,
                       "Three valid rows; the junk line is skipped, not fatal")
    }

    func testLocalAdapterReportsUnavailableRatherThanInventingNumbers() async throws {
        // An empty home: no CLI has ever run here.
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tidemark-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let snapshot = await LocalActivityDataSource(home: home).fetch(now: Date())
        XCTAssertFalse(snapshot.providers.isEmpty, "Providers are still listed, so the user knows they exist")
        for provider in snapshot.providers {
            XCTAssertTrue(provider.state.hasNoData)
            XCTAssertNil(provider.usedFraction, "No data must mean no number, not a zero")
            XCTAssertFalse(provider.state.explanation.isEmpty, "It has to say why")
        }
        XCTAssertTrue(snapshot.sessions.isEmpty)
    }

    func testLocalAdapterMarksItsUsageFigureAsEstimatedNotMeasured() async throws {
        let home = try makeFixtureHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let snapshot = await LocalActivityDataSource(home: home).fetch(now: Date())
        let reporting = snapshot.providers.filter { $0.usedFraction != nil }
        for provider in reporting {
            XCTAssertEqual(provider.confidence, .estimated,
                           "The percentage is a local proxy, so it must never claim to be measured")
            XCTAssertTrue(provider.sourceDescription.lowercased().contains("not a plan limit"))
        }
    }

    func testCostModelStatesItsAssumption() {
        let model = LocalActivityDataSource.CostModel(tokensPerMessage: 1_000, dollarsPerMillionTokens: 5)
        XCTAssertEqual(model.estimate(messages: 1_000), 5.0, accuracy: 0.0001)
        XCTAssertTrue(model.assumption.contains("1000"))
        XCTAssertTrue(model.assumption.lowercased().contains("not billing data"))
    }

    func testProvenanceIsNonEmptyForBothAdapters() {
        XCTAssertFalse(LocalActivityDataSource().provenance.isEmpty)
        XCTAssertFalse(MockUsageDataSource().provenance.isEmpty)
    }
}
