import Foundation
import AppKit
import Combine

/// Central app state: volume monitoring, disk scans, audits, and deletions.
@MainActor
public final class AppModel: ObservableObject {
    // MARK: - Volume monitoring

    public let volumeMonitor = VolumeMonitor()

    // MARK: - Folder watcher

    public let watch = WatchService()

    // MARK: - Disk tree

    @Published public var diskRoot: DiskNode?
    @Published public var isScanning = false
    @Published public var scanProgress = ScanProgress.empty
    @Published public var scanWasCancelled = false
    @Published public var lastScanDate: Date?
    @Published public var scanRootPath: String = ""

    private var scanTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    // MARK: - Ollama audit

    @Published public var ollamaAudit: OllamaAudit?
    @Published public var isAuditingOllama = false

    // MARK: - llama.cpp audit

    @Published public var llamaAudit: LlamaAudit?
    @Published public var isAuditingLlama = false

    // MARK: - Developer caches audit

    @Published public var cachesAudit: CachesAudit?
    @Published public var isAuditingCaches = false

    // MARK: - Time Machine local snapshots

    @Published public var snapshots: [SnapshotInfo] = []
    @Published public var snapshotWarnings: [String] = []
    @Published public var isAuditingSnapshots = false
    @Published public var lastThinResult: String?

    // MARK: - Deletion feedback

    @Published public var lastDeletionSummary: String?

    public init() {
        Task { await watch.check() }
    }

    // MARK: - Settings passthrough

    public var customGGUFFolders: [String] {
        let raw = UserDefaults.standard.string(forKey: "customGGUFFolders") ?? ""
        let stored = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        // An explicitly saved empty list must win over the default (so the
        // default folder can actually be removed).
        if UserDefaults.standard.object(forKey: "customGGUFFolders") != nil {
            return stored
        }
        return stored.isEmpty ? LlamaAuditor.defaultCustomFolders : stored
    }

    public var sourceScanRoots: [String] {
        let raw = UserDefaults.standard.string(forKey: "sourceScanRoots") ?? ""
        let stored = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if UserDefaults.standard.object(forKey: "sourceScanRoots") != nil {
            return stored
        }
        return stored.isEmpty ? LlamaAuditor.defaultSourceRoots : stored
    }

    public var deleteMode: DeletionMode {
        get { TrashService.deleteMode }
        set { TrashService.deleteMode = newValue }
    }

    // MARK: - Disk scanning

    public func scanDisk(root: URL? = nil) {
        guard !isScanning else { return }
        let target = root ?? FileManager.default.homeDirectoryForCurrentUser
        scanRootPath = target.path
        isScanning = true
        scanWasCancelled = false
        scanProgress = .empty
        diskRoot = nil

        let stats = ScanStats()
        let scanner = DiskScanner(root: target, stats: stats)

        scanTask = Task {
            let node = await scanner.scan()
            if Task.isCancelled {
                self.scanWasCancelled = true
            } else {
                self.diskRoot = node
                self.lastScanDate = Date()
            }
            self.isScanning = false
            self.progressTask?.cancel()
        }

        progressTask = Task {
            while !Task.isCancelled {
                let snapshot = await Self.progressSnapshot(stats)
                if !Task.isCancelled {
                    self.scanProgress = snapshot
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
    }

    private static func progressSnapshot(_ stats: ScanStats) async -> ScanProgress {
        var progress = ScanProgress()
        progress.phase = "Scanning"
        progress.currentItem = await stats.currentItem
        progress.scannedItems = await stats.items
        progress.scannedBytes = await stats.bytes
        return progress
    }

    // MARK: - Audits

    public func runOllamaAudit() {
        guard !isAuditingOllama else { return }
        isAuditingOllama = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { OllamaAuditor().audit() }.value
            self.ollamaAudit = result
            self.isAuditingOllama = false
        }
    }

    public func runLlamaAudit() {
        guard !isAuditingLlama else { return }
        isAuditingLlama = true
        let folders = customGGUFFolders
        let roots = sourceScanRoots
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LlamaAuditor(customFolders: folders, sourceScanRoots: roots).audit()
            }.value
            self.llamaAudit = result
            self.isAuditingLlama = false
        }
    }

    public func runCachesAudit() {
        guard !isAuditingCaches else { return }
        isAuditingCaches = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { XcodeCachesAuditor().audit() }.value
            self.cachesAudit = result
            self.isAuditingCaches = false
        }
    }

    public func runSnapshotAudit() {
        guard !isAuditingSnapshots else { return }
        isAuditingSnapshots = true
        Task {
            let listing = await Task.detached(priority: .userInitiated) { TMSnapshots.list() }.value
            self.snapshots = listing.snapshots
            self.snapshotWarnings = listing.warnings
            self.isAuditingSnapshots = false
        }
    }

    public func thinSnapshots() {
        isAuditingSnapshots = true
        Task {
            let output = await Task.detached(priority: .userInitiated) {
                TMSnapshots.thin(targetBytes: 20_000_000_000) // ask for up to 20 GB
            }.value
            self.lastThinResult = output?.isEmpty == false
                ? output
                : "tmutil thinlocalsnapshots returned no output (nothing to thin, or not permitted)."
            self.isAuditingSnapshots = false
            self.runSnapshotAudit()
        }
    }

    // MARK: - Deletion

    /// Deletes arbitrary file paths, then refreshes the relevant audit.
    public func deleteFiles(at urls: [URL], mode: DeletionMode? = nil, refresh: RefreshTarget = []) {
        let effectiveMode = mode ?? deleteMode
        guard !urls.isEmpty else { return }
        let outcomes = TrashService.delete(urls, mode: effectiveMode)
        report(outcomes: outcomes, mode: effectiveMode)
        refreshAfter(refresh)
    }

    /// Trash-only orphan cleanup. **Re-verifies against a fresh audit before
    /// deleting** — a running Ollama server may have referenced a previously
    /// orphaned blob in a new pull since the on-screen audit ran. Blobs that
    /// are no longer orphans are skipped, never deleted.
    /// - Parameter urls: explicit blob URLs, or nil for all current orphans.
    public func cleanOrphanedBlobs(urls: [URL]? = nil) {
        guard !isAuditingOllama else { return }
        isAuditingOllama = true
        let requested = urls

        Task {
            let plan = await Task.detached(priority: .userInitiated) { () -> (delete: [URL], skipped: Int, audit: OllamaAudit) in
                let fresh = OllamaAuditor().audit()
                let stillOrphaned = Set(fresh.orphanedBlobs.map { $0.url.path })
                let toDelete = requested?.filter { stillOrphaned.contains($0.path) }
                    ?? fresh.orphanedBlobs.map { $0.url }
                let skipped = (requested?.count ?? fresh.orphanedBlobs.count) - toDelete.count
                return (toDelete, skipped, fresh)
            }.value

            let outcomes = TrashService.delete(plan.delete, mode: .trash)
            self.ollamaAudit = plan.audit
            self.isAuditingOllama = false

            let failed = outcomes.filter { !$0.success }.count
            var summary = "Moved \(outcomes.count - failed) orphaned blob\(outcomes.count - failed == 1 ? "" : "s") to Trash."
            if plan.skipped > 0 {
                summary += " \(plan.skipped) skipped — now referenced by a model."
            }
            if failed > 0 {
                summary += " \(failed) failed: \(outcomes.first(where: { !$0.success })?.message ?? "error")"
            }
            self.lastDeletionSummary = summary
            self.runOllamaAudit()
        }
    }

    /// Deletes an Ollama model: its manifest plus blobs referenced only by it.
    /// Always Trash (the confirming dialog advertises Trash semantics), and
    /// re-verified against a fresh audit at deletion time — the model set and
    /// blob sharing may have changed since the on-screen audit ran.
    public func deleteOllamaModel(_ model: OllamaModelInfo) {
        guard !isAuditingOllama else { return }
        isAuditingOllama = true
        let manifestPath = model.manifestURL.path

        Task {
            let plan = await Task.detached(priority: .userInitiated) { () -> (urls: [URL], audit: OllamaAudit)? in
                let fresh = OllamaAuditor().audit()
                guard let freshModel = fresh.models.first(where: { $0.manifestURL.path == manifestPath }) else {
                    return nil
                }
                let blobs = OllamaAuditor.blobsUniqueTo(model: freshModel, allModels: fresh.models, blobs: fresh.allBlobs)
                var urls = blobs.map { $0.url }
                urls.append(freshModel.manifestURL)
                return (urls, fresh)
            }.value

            self.isAuditingOllama = false
            self.ollamaAudit = plan?.audit

            guard let plan else {
                self.lastDeletionSummary = "Model no longer present — nothing deleted."
                self.runOllamaAudit()
                return
            }
            let outcomes = TrashService.delete(plan.urls, mode: .trash)
            self.report(outcomes: outcomes, mode: .trash)
            self.runOllamaAudit()
        }
    }

    /// Removes a node from the in-memory disk tree and deletes it on disk.
    public func deleteDiskNode(_ node: DiskNode, mode: DeletionMode? = nil) {
        deleteFiles(at: [node.url], mode: mode, refresh: [])
        guard let root = diskRoot else { return }
        if root.path == node.path {
            diskRoot = nil
        } else {
            diskRoot = root.removing(path: node.path)
        }
    }

    /// Deletes selected developer-cache items (always Trash).
    public func cleanCacheItems(_ items: [CacheItem]) {
        guard !items.isEmpty else { return }
        let outcomes = TrashService.delete(items.map { $0.url }, mode: .trash)
        report(outcomes: outcomes, mode: .trash)
        runCachesAudit()
    }

    private func report(outcomes: [DeleteOutcome], mode: DeletionMode) {
        let failed = outcomes.filter { !$0.success }
        let verb = mode == .trash ? "Moved to Trash" : "Deleted"
        if failed.isEmpty {
            lastDeletionSummary = "\(verb) \(outcomes.count) item\(outcomes.count == 1 ? "" : "s")."
        } else {
            lastDeletionSummary = "\(verb) \(outcomes.count - failed.count), failed \(failed.count): \(failed.first?.message ?? "unknown error")"
        }
    }

    // MARK: - Report export

    /// Writes a JSON audit report next to where the user chooses; returns the URL.
    public func exportReport() -> URL? {
        let report = Self.synchronousReport()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "macspaces-audit.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard ScheduledAudit.isSafeWriteTarget(url) else {
            lastDeletionSummary = "Report save refused: target is a symlink or its folder is missing."
            return nil
        }
        do {
            let data = try JSONEncoder.macSpaces.encode(report)
            try data.write(to: url)
            lastDeletionSummary = "Report saved to \(Format.tildify(url.path))."
            return url
        } catch {
            lastDeletionSummary = "Report save failed: \(error.localizedDescription)"
            return nil
        }
    }

    /// Same pipeline the CLI uses (feature: report export / CLI companion).
    nonisolated public static func synchronousReport() -> AuditReport {
        ScheduledAudit.run()
    }

    // MARK: - Refresh targets

    public struct RefreshTarget: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let ollama = RefreshTarget(rawValue: 1 << 0)
        public static let llama = RefreshTarget(rawValue: 1 << 1)
        public static let disk = RefreshTarget(rawValue: 1 << 2)
        public static let caches = RefreshTarget(rawValue: 1 << 3)
    }

    private func refreshAfter(_ targets: RefreshTarget) {
        if targets.contains(.ollama) { runOllamaAudit() }
        if targets.contains(.llama) { runLlamaAudit() }
        if targets.contains(.caches) { runCachesAudit() }
        if targets.contains(.disk) {
            if !scanRootPath.isEmpty {
                scanDisk(root: URL(fileURLWithPath: scanRootPath))
            }
        }
    }
}
