import Foundation
import Combine

/// Central app state: volume monitoring, disk scans, audits, and deletions.
@MainActor
public final class AppModel: ObservableObject {
    // MARK: - Volume monitoring

    public let volumeMonitor = VolumeMonitor()

    public init() {}

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

    // MARK: - Deletion feedback

    @Published public var lastDeletionSummary: String?

    // MARK: - Settings passthrough

    public var customGGUFFolders: [String] {
        let raw = UserDefaults.standard.string(forKey: "customGGUFFolders") ?? ""
        let defaults = LlamaAuditor.defaultCustomFolders
        let stored = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return stored.isEmpty ? defaults : stored
    }

    public var sourceScanRoots: [String] {
        let raw = UserDefaults.standard.string(forKey: "sourceScanRoots") ?? ""
        let defaults = LlamaAuditor.defaultSourceRoots
        let stored = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return stored.isEmpty ? defaults : stored
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
                let statsSnapshot = await stats.snapshot()
                if !Task.isCancelled {
                    self.scanProgress = statsSnapshot
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    public func cancelScan() {
        scanTask?.cancel()
    }

    // MARK: - Audits

    public func runOllamaAudit() {
        guard !isAuditingOllama else { return }
        isAuditingOllama = true
        Task {
            let auditor = OllamaAuditor()
            let result = await Task.detached(priority: .userInitiated) { auditor.audit() }.value
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

    // MARK: - Deletion

    /// Deletes arbitrary file paths, then refreshes the relevant audit.
    public func deleteFiles(at urls: [URL], mode: DeletionMode? = nil, refresh: RefreshTarget = []) {
        let effectiveMode = mode ?? deleteMode
        guard !urls.isEmpty else { return }
        let outcomes = TrashService.delete(urls, mode: effectiveMode)
        report(outcomes: outcomes, mode: effectiveMode)
        refreshAfter(refresh)
    }

    /// Moves every orphaned Ollama blob to the Trash (always trash-safe).
    public func deleteOrphanedBlobs() {
        guard let blobs = ollamaAudit?.orphanedBlobs, !blobs.isEmpty else { return }
        let urls = blobs.map { $0.url }
        let outcomes = TrashService.delete(urls, mode: .trash)
        report(outcomes: outcomes, mode: .trash)
        runOllamaAudit()
    }

    /// Deletes an Ollama model: its manifest plus blobs referenced only by it.
    public func deleteOllamaModel(_ model: OllamaModelInfo, mode: DeletionMode? = nil) {
        guard let audit = ollamaAudit else { return }
        let uniqueBlobs = OllamaAuditor.blobsUniqueTo(model: model, allModels: audit.models, blobs: audit.allBlobs)
        var urls = uniqueBlobs.map { $0.url }
        urls.append(model.manifestURL)
        let effectiveMode = mode ?? deleteMode
        let outcomes = TrashService.delete(urls, mode: effectiveMode)
        report(outcomes: outcomes, mode: effectiveMode)
        runOllamaAudit()
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

    private func report(outcomes: [DeleteOutcome], mode: DeletionMode) {
        let failed = outcomes.filter { !$0.success }
        let verb = mode == .trash ? "Moved to Trash" : "Deleted"
        if failed.isEmpty {
            lastDeletionSummary = "\(verb) \(outcomes.count) item\(outcomes.count == 1 ? "" : "s")."
        } else {
            lastDeletionSummary = "\(verb) \(outcomes.count - failed.count), failed \(failed.count): \(failed.first?.message ?? "unknown error")"
        }
    }

    // MARK: - Refresh targets

    public struct RefreshTarget: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let ollama = RefreshTarget(rawValue: 1 << 0)
        public static let llama = RefreshTarget(rawValue: 1 << 1)
        public static let disk = RefreshTarget(rawValue: 1 << 2)
    }

    private func refreshAfter(_ targets: RefreshTarget) {
        if targets.contains(.ollama) { runOllamaAudit() }
        if targets.contains(.llama) { runLlamaAudit() }
        if targets.contains(.disk) {
            if let path = scanRootPath.isEmpty ? nil : URL(fileURLWithPath: scanRootPath) {
                scanDisk(root: path)
            }
        }
    }
}

private extension ScanStats {
    func snapshot() async -> ScanProgress {
        var progress = ScanProgress()
        progress.phase = "Scanning"
        progress.currentItem = await self.currentItem
        progress.scannedItems = await self.items
        progress.scannedBytes = await self.bytes
        return progress
    }
}
