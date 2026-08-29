import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
let rateLimits = payload["rate_limits"] as? [String: Any]
let hasLimits = rateLimits?.isEmpty == false
let captured = Date().timeIntervalSince1970

var capture: [String: Any] = [
    "captured_at_epoch": captured,
    "rate_limits": hasLimits ? rateLimits as Any : NSNull()
]
if let model = payload["model"] as? [String: Any],
   let displayName = model["display_name"] as? String {
    capture["model"] = displayName
}

let home = FileManager.default.homeDirectoryForCurrentUser
let destination = home.appendingPathComponent(".metr/statusline/latest.json")
let directory = destination.deletingLastPathComponent()
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
if JSONSerialization.isValidJSONObject(capture),
   let data = try? JSONSerialization.data(withJSONObject: capture, options: [.sortedKeys]) {
    // `.atomic` ensures metr never observes a partially-written statusline.
    try? data.write(to: destination, options: .atomic)
}

func cleanPercent(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber else { return nil }
    let percent = number.doubleValue
    guard percent.isFinite, percent >= 0, percent <= 101 else { return nil }
    return min(100, percent)
}

var output: [String] = []
if let displayName = capture["model"] as? String, !displayName.isEmpty { output.append(displayName) }
for (label, key) in [("5h", "five_hour"), ("7d", "seven_day")] {
    if let window = rateLimits?[key] as? [String: Any],
       let percent = cleanPercent(window["used_percentage"]) {
        output.append("\(label) \(Int(percent.rounded()))%")
    }
}
print(output.isEmpty ? "metr" : output.joined(separator: " · "))
