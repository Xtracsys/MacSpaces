import Foundation

/// Lists and thins APFS local Time Machine snapshots via `tmutil`.
/// Sizes are not reported (tmutil does not expose them reliably); snapshot
/// storage is purgeable space that Free-space numbers already account for.
public enum TMSnapshots {
    public struct Listing {
        public let snapshots: [SnapshotInfo]
        public let warnings: [String]
    }

    /// Parses `tmutil listlocalsnapshots <mount>`:
    /// lines like "com.apple.TimeMachine.2026-10-29-121212.local".
    public static func list(mountPoint: String = "/") -> Listing {
        guard let output = run(["/usr/bin/tmutil", "listlocalsnapshots", mountPoint]) else {
            return Listing(snapshots: [], warnings: ["tmutil could not be executed."])
        }

        var snapshots: [SnapshotInfo] = []
        var warnings: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = .current

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("com.apple.TimeMachine.") else {
                if !trimmed.isEmpty, !trimmed.hasPrefix("Snapshots for") {
                    warnings.append(trimmed)
                }
                continue
            }
            var stamp = trimmed
            if stamp.hasSuffix(".local") { stamp = String(stamp.dropLast(".local".count)) }
            stamp = String(stamp.dropFirst("com.apple.TimeMachine.".count))
            snapshots.append(SnapshotInfo(name: trimmed, date: formatter.date(from: stamp)))
        }
        return Listing(snapshots: snapshots, warnings: warnings)
    }

    /// Asks the system to thin local snapshots until `targetBytes` are freed.
    /// Requires no special privileges; returns tmutil's progress output.
    public static func thin(targetBytes: Int64, mountPoint: String = "/") -> String? {
        run([
            "/usr/bin/tmutil", "thinlocalsnapshots", mountPoint,
            String(targetBytes), "4",
        ])
    }

    static func run(_ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: arguments[0]) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || !data.isEmpty else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
