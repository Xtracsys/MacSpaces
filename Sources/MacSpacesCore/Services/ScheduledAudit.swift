import Foundation
import AppKit

/// Headless audit modes. The app binary doubles as a CLI companion:
///   MacSpaces --audit-json      run audits, print a JSON report to stdout, exit
///   MacSpaces --scheduled-audit run audits, write the report + post a digest
///                               notification, exit (used by the launchd agent)
public enum ScheduledAudit {
    public static let launchAgentLabel = "com.macspaces.audit"

    /// Returns true when a CLI mode handled the launch and the caller should exit.
    @discardableResult
    public static func handleLaunchArguments(arguments: [String] = CommandLine.arguments) -> Bool {
        if arguments.contains("--audit-json") {
            let report = run()
            if let data = try? JSONEncoder.macSpaces.encode(report) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            } else {
                print("{}")
            }
            return true
        }
        if arguments.contains("--scheduled-audit") {
            let report = run()
            writeReport(report)
            notify(report)
            return true
        }
        return false
    }

    /// Runs every audit synchronously (CLI context — no UI to keep responsive).
    public static func run() -> AuditReport {
        let monitor = VolumeInfoSource()
        let ollama = OllamaAuditor().audit()
        let llama = LlamaAuditor().audit()
        let caches = XcodeCachesAuditor().audit()

        return AuditReport(
            generatedAt: Date(),
            volumes: monitor.volumes.map {
                .init(name: $0.name, freeBytes: $0.availableCapacity, totalBytes: $0.totalCapacity)
            },
            ollama: .init(
                installed: ollama.ollamaHome != nil,
                running: ollama.ollamaRunning,
                modelCount: ollama.models.count,
                modelBytes: ollama.modelsBytes,
                orphanCount: ollama.orphanedBlobs.count,
                orphanBytes: ollama.orphanedBytes,
                models: ollama.models.map {
                    .init(name: $0.qualifiedName, totalBytes: $0.totalSize, uniqueBytes: $0.uniqueSize)
                }
            ),
            llama: .init(
                installCount: llama.installs.count,
                modelLocationCount: llama.modelDirs.count,
                ggufBytes: llama.ggufBytes,
                duplicateGroupCount: llama.duplicateGroups.count,
                duplicateReclaimableBytes: llama.duplicateReclaimableBytes
            ),
            caches: .init(itemCount: caches.items.count, totalBytes: caches.totalBytes)
        )
    }

    // MARK: - Persistence

    public static var reportDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSpaces")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var reportURL: URL {
        reportDirectory.appendingPathComponent("last-audit.json")
    }

    public static func writeReport(_ report: AuditReport) {
        if let data = try? JSONEncoder.macSpaces.encode(report),
           Self.isSafeWriteTarget(reportURL) {
            try? data.write(to: reportURL)
        }
    }

    /// True when `url` is safe to overwrite: it must not be a symlink (a
    /// planted link would redirect the write elsewhere) and its parent
    /// directory must exist. Defense-in-depth for fixed-path writes.
    public static func isSafeWriteTarget(_ url: URL) -> Bool {
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil { return false }
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Digest notification via osascript (works from launchd context without
    /// notification-center entitlements).
    public static func notify(_ report: AuditReport) {
        let reclaimable = report.ollama.orphanBytes + report.llama.duplicateReclaimableBytes
        let message = reclaimable > 0
            ? "Audit done: \(Format.bytes(reclaimable)) reclaimable (\(report.ollama.orphanCount) orphans, \(report.llama.duplicateGroupCount) duplicate groups)."
            : "Audit done: no reclaimable AI-model space found. \(Format.bytes(report.ollama.modelBytes)) in \(report.ollama.modelCount) models."
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "display notification \"\(message)\" with title \"MacSpaces\"",
        ]
        try? process.run()
    }

    // MARK: - launchd agent (weekly digest)

    public static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    /// True when the weekly-audit launchd agent is installed.
    public static var isLaunchAgentInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    /// Installs (or removes) a launchd agent running `--scheduled-audit`
    /// every Friday at 10:00.
    @discardableResult
    public static func setLaunchAgent(enabled: Bool) -> Bool {
        let fm = FileManager.default
        if !enabled {
            _ = TMSnapshots.run(["/bin/launchctl", "unload", launchAgentURL.path])
            try? fm.removeItem(at: launchAgentURL)
            return true
        }

        guard let executable = Bundle.main.executableURL?.path else { return false }
        let agentsDir = launchAgentURL.deletingLastPathComponent()
        try? fm.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [executable, "--scheduled-audit"],
            "StartCalendarInterval": [
                ["Weekday": 5, "Hour": 10, "Minute": 0],
            ],
            "RunAtLoad": false,
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        ), isSafeWriteTarget(launchAgentURL) else { return false }
        do {
            try data.write(to: launchAgentURL)
        } catch {
            return false
        }
        _ = TMSnapshots.run(["/bin/launchctl", "load", launchAgentURL.path])
        return true
    }
}

/// Convenience so the CLI path can read volumes without a MainActor timer.
struct VolumeInfoSource {
    var volumes: [VolumeInfo] {
        let fm = FileManager.default
        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ], options: [.skipHiddenVolumes]) ?? []

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [
                .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            ])
            guard let total = values?.volumeTotalCapacity, total > 0 else { return nil }
            return VolumeInfo(
                url: url,
                name: values?.volumeName ?? url.lastPathComponent,
                totalCapacity: Int64(total),
                availableCapacity: Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
            )
        }.sorted { a, b in
            if a.url.path == "/" { return true }
            if b.url.path == "/" { return false }
            return a.name < b.name
        }
    }
}

extension JSONEncoder {
    /// Pretty-printed ISO-8601 encoder used for all MacSpaces report JSON.
    static var macSpaces: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
