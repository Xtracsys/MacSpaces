import Foundation

/// A counting semaphore usable from async contexts; `signal()` is synchronous
/// so it can be used outside a holding scope.
final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ value: Int) {
        available = value
    }

    func wait() async {
        lock.lock()
        if available > 0 {
            available -= 1
            lock.unlock()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
            lock.unlock()
        }
    }

    /// Release the permit WITHOUT awaiting — safe from synchronous code.
    func signal() {
        lock.lock()
        let continuation = waiters.isEmpty ? nil : waiters.removeFirst()
        if continuation == nil { available += 1 }
        lock.unlock()
        continuation?.resume()
    }
}

/// Accumulates scan statistics from concurrent workers.
actor ScanStats {
    private(set) var items: Int = 0
    private(set) var bytes: Int64 = 0
    private(set) var currentItem: String = ""

    func record(items: Int, bytes: Int64, path: String) {
        self.items += items
        self.bytes += bytes
        self.currentItem = path
    }
}

/// Recursively sizes a directory tree using a bounded pool of concurrent tasks.
struct DiskScanner {
    static let defaultConcurrency = 12

    /// Directory names skipped anywhere in the tree (noise / kernel-owned).
    static let skippedDirectoryNames: Set<String> = [
        ".Spotlight-V100", ".fseventsd", ".Trashes", ".DocumentRevisions-V100",
        ".MobileBackups", ".TemporaryItems", ".PKInstallSandboxManagerSystemSoftware",
    ]

    /// Absolute path prefixes skipped when scanning from the filesystem root,
    /// to avoid double counting APFS firmlinks and kernel-owned paths.
    static let skippedRootPrefixes: [String] = [
        "/System/Volumes", "/dev", "/private/var/vm", "/Volumes", "/.Spotlight-V100",
        "/.fseventsd", "/.DocumentRevisions-V100", "/private/tmp", "/cores",
    ]

    static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
        .fileSizeKey, .totalFileAllocatedSizeKey, .isReadableKey,
    ]

    let root: URL
    let stats: ScanStats?
    private let semaphore: AsyncSemaphore

    init(root: URL, concurrency: Int = DiskScanner.defaultConcurrency, stats: ScanStats? = nil) {
        self.root = root
        self.stats = stats
        self.semaphore = AsyncSemaphore(max(1, concurrency))
    }

    func scan() async -> DiskNode {
        let node = await scanDirectory(root)
        return node ?? DiskNode(
            path: root.path, name: root.lastPathComponent, isDirectory: true,
            ownBytes: 0, totalBytes: 0, itemCount: 1, children: [], accessDenied: true
        )
    }

    static func shouldSkip(path: String, scanRoot: String) -> Bool {
        if scanRoot == "/" {
            for prefix in skippedRootPrefixes where path.hasPrefix(prefix) {
                return true
            }
        }
        let name = (path as NSString).lastPathComponent
        return skippedDirectoryNames.contains(name)
    }

    private func scanDirectory(_ dir: URL) async -> DiskNode? {
        if Task.isCancelled { return nil }

        await semaphore.wait()

        // --- Enumeration happens while holding the permit -------------------
        var ownBytes: Int64 = 0
        var itemCount = 1
        var subdirectories: [URL] = []

        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: Array(Self.resourceKeys), options: []
            )
            for entry in entries {
                if Task.isCancelled { break }
                let path = entry.path
                if Self.shouldSkip(path: path, scanRoot: root.path) { continue }
                if IgnoreRules.shared.excludes(path: path) { continue }

                let values = try? entry.resourceValues(forKeys: Self.resourceKeys)
                if values?.isSymbolicLink == true { continue }

                if values?.isDirectory == true {
                    subdirectories.append(entry)
                    // No +1 here: the child node's own itemCount already
                    // includes itself — counting both double-counts dirs.
                } else {
                    let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                    ownBytes += size
                    itemCount += 1
                    await stats?.record(items: 1, bytes: size, path: path)
                }
            }
        } catch {
            semaphore.signal()
            await stats?.record(items: 0, bytes: 0, path: dir.path)
            return DiskNode(
                path: dir.path, name: dir.lastPathComponent, isDirectory: true,
                ownBytes: 0, totalBytes: 0, itemCount: 1, children: [],
                accessDenied: true
            )
        }

        // --- Release the permit BEFORE waiting on children ------------------
        // Holding a permit across the child TaskGroup deadlocks the bounded
        // pool on deep trees: N blocked parents can hold all N permits while
        // their children wait for one forever.
        semaphore.signal()

        var children: [DiskNode] = []
        if !subdirectories.isEmpty && !Task.isCancelled {
            let nodes = await withTaskGroup(
                of: DiskNode?.self, returning: [DiskNode?].self
            ) { group in
                for sub in subdirectories {
                    group.addTask { await self.scanDirectory(sub) }
                }
                var results: [DiskNode?] = []
                for await node in group { results.append(node) }
                return results
            }
            for node in nodes {
                guard let node else { continue }
                children.append(node)
                itemCount += node.itemCount
            }
        }

        let childBytes = children.reduce(Int64(0)) { $0 + $1.totalBytes }
        return DiskNode(
            path: dir.path,
            name: dir.lastPathComponent,
            isDirectory: true,
            ownBytes: ownBytes,
            totalBytes: ownBytes + childBytes,
            itemCount: itemCount,
            children: children.sorted { $0.totalBytes > $1.totalBytes },
            accessDenied: false
        )
    }

    /// One-shot sequential size of a directory tree (for small footprints).
    static func sequentialSize(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if IgnoreRules.shared.excludes(path: path) { continue }
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true || values?.isSymbolicLink == true { continue }
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
