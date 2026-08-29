import XCTest
@testable import MetrKit

final class ProviderQuotaClientTests: XCTestCase {
    func testCodexRoutesShortestReportedWindow() {
        let now = Date().timeIntervalSince1970
        let reading = ProviderQuotaClient.selectCodexWindow([
            "primary_window": ["used_percent": 41.0, "reset_at": now + 600, "limit_window_seconds": 604_800.0],
            "secondary_window": ["used_percent": 12.0, "reset_at": now + 300, "limit_window_seconds": 18_000.0]
        ])
        XCTAssertEqual(reading?.fraction, 0.12)
        XCTAssertEqual(reading?.label, "5-hour window")
    }

    func testCodexSingleWeeklyWindowRemainsWeekly() {
        let reading = ProviderQuotaClient.selectCodexWindow([
            "primary_window": ["used_percent": 67.0, "limit_window_seconds": 604_800.0]
        ])
        XCTAssertEqual(reading?.fraction, 0.67)
        XCTAssertEqual(reading?.label, "7-day window")
    }

    func testCodexRetainsImmediateAndWeeklyWindows() {
        let readings = ProviderQuotaClient.codexWindows([
            "primary_window": ["used_percent": 61.0, "limit_window_seconds": 604_800.0],
            "secondary_window": ["used_percent": 18.0, "limit_window_seconds": 18_000.0]
        ])
        XCTAssertEqual(readings.map(\.label), ["5-hour window", "7-day window"])
        XCTAssertEqual(readings.map(\.fraction), [0.18, 0.61])
    }

    func testClaudeAlwaysTreatsUtilizationAsPercent() {
        let reading = ProviderQuotaClient.parseClaudeWindow([
            "utilization": 0.5,
            "resets_at": "2026-08-30T12:00:00Z"
        ])
        XCTAssertEqual(reading?.fraction, 0.005)
        XCTAssertNotNil(reading?.resetAt)

        let official = ProviderQuotaClient.parseClaudeWindow(["used_percentage": 12.0])
        XCTAssertEqual(official?.fraction, 0.12, "Claude Code statusLine uses used_percentage")
    }

    func testClaudeRetainsImmediateAndWeeklyWindows() {
        let readings = ProviderQuotaClient.claudeWindows([
            "five_hour": ["utilization": 12.0],
            "seven_day": ["utilization": 46.0]
        ])
        XCTAssertEqual(readings.map(\.label), ["5-hour window", "7-day window"])
        XCTAssertEqual(readings.map(\.fraction), [0.12, 0.46])
    }

    func testParsersClampOutOfRangeUsage() {
        XCTAssertEqual(ProviderQuotaClient.parseCodexWindow(["used_percent": 180.0])?.fraction, 1)
        XCTAssertEqual(ProviderQuotaClient.parseClaudeWindow(["utilization": -20.0])?.fraction, 0)
    }
}
