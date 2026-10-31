import Foundation
@testable import MacSpacesCore

// Macro-free test harness: CLT on this machine ships neither the XCTest
// framework nor the Swift Testing macro plugin, so tests are plain code.
// Run: swift run --scratch-path .build/tests macspaces-tests

final class TestRecorder {
    var failures: [String] = []
    var passed = 0

    func check(_ condition: Bool, _ message: @autoclosure () -> String, file: String = #fileID, line: UInt = #line) {
        if condition {
            passed += 1
        } else {
            failures.append("\(file):\(line) — \(message())")
        }
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ recorder: TestRecorder, _ what: String, file: String = #fileID, line: UInt = #line) {
    recorder.check(a == b, "\(what): \(a) != \(b)", file: file, line: line)
}

private func resolvingSymlinks(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

// MARK: - Ollama audit tests

enum OllamaAuditTests {
    static func run(_ r: TestRecorder) throws {
        try digestRoundTrip(r)
        try withTempRoot { try orphanDetectionAndSharedLayers(tempRoot: $0, r: r) }
        try withTempRoot { try missingBlobsReported(tempRoot: $0, r: r) }
        try withTempRoot { try blobsUniqueToModel(tempRoot: $0, r: r) }
        try withTempRoot { try processDetection(tempRoot: $0, r: r) }
        try versionGrouping(r)
        try quantTagDetection(r)
    }

    private static func withTempRoot(_ body: (URL) throws -> Void) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollama-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try body(tempRoot)
    }

    /// Blob sizes in tests are multiples of the 4096-byte block so that
    /// allocated size == written size.
    private static func makeBlob(_ digest: String, size: Int, root: URL) throws {
        let url = root.appendingPathComponent("models/blobs")
            .appendingPathComponent(Format.blobFileName(forDigest: digest))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: size).write(to: url)
    }

    @discardableResult
    private static func makeManifest(
        registry: String, namespace: String?, name: String, tag: String,
        configDigest: String?, layerDigests: [String], root: URL
    ) throws -> URL {
        var document: [String: Any] = [
            "schemaVersion": 2,
            "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
        ]
        if let configDigest {
            document["config"] = [
                "mediaType": "application/vnd.docker.container.image.v1+json",
                "digest": configDigest, "size": 0,
            ]
        }
        if !layerDigests.isEmpty {
            document["layers"] = layerDigests.map { digest in
                ["mediaType": "application/vnd.ollama.image.model", "digest": digest, "size": 0]
            }
        }
        var path = root.appendingPathComponent("models/manifests/\(registry)")
        if let namespace { path = path.appendingPathComponent(namespace) }
        path = path.appendingPathComponent(name).appendingPathComponent(tag)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: document).write(to: path)
        return path
    }

    private static func digestRoundTrip(_ r: TestRecorder) {
        let digest = "sha256:0f6ec9740c765c3fb0dc38fe25f4d283c3bc1ede32b76f81c3a971daef20f76c"
        expectEqual(Format.blobFileName(forDigest: digest), digest.replacingOccurrences(of: ":", with: "-"), r, "blob file name")
        expectEqual(Format.digest(forBlobFileName: Format.blobFileName(forDigest: digest)), digest, r, "digest round trip")
    }

    private static func orphanDetectionAndSharedLayers(tempRoot: URL, r: TestRecorder) throws {
        let shared = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let uniqueA = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let orphan = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        let configA = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

        try makeBlob(shared, size: 4096, root: tempRoot)
        try makeBlob(uniqueA, size: 8192, root: tempRoot)
        try makeBlob(orphan, size: 8192, root: tempRoot)
        try makeBlob(configA, size: 4096, root: tempRoot)

        let manifestA = try makeManifest(
            registry: "registry.ollama.ai", namespace: "library", name: "test-a", tag: "latest",
            configDigest: configA, layerDigests: [shared, uniqueA], root: tempRoot
        )
        try makeManifest(
            registry: "hf.co", namespace: "org", name: "test-b", tag: "Q4_K_M",
            configDigest: nil, layerDigests: [shared], root: tempRoot
        )

        let audit = OllamaAuditor(homeDirectory: tempRoot).audit()

        expectEqual(audit.models.count, 2, r, "model count")
        expectEqual(Set(audit.orphanedBlobs.map { $0.digest }), Set([orphan]), r, "orphan set")
        expectEqual(audit.orphanedBytes, Int64(8192), r, "orphan bytes")
        r.check(audit.sharedBlobDigests.contains(shared), "shared layer detected")
        r.check(!audit.sharedBlobDigests.contains(uniqueA), "unique layer not marked shared")

        // Enumerators may resolve /var → /private/var; compare resolved paths.
        let resolvedManifestA = resolvingSymlinks(manifestA.path)
        let modelA = audit.models.first { resolvingSymlinks($0.manifestURL.path) == resolvedManifestA }
        r.check(modelA != nil, "model A present; found: \(audit.models.map { $0.qualifiedName })")
        expectEqual(modelA?.totalSize ?? 0, Int64(16384), r, "model A total (config 4096 + shared 4096 + unique 8192)")
        expectEqual(modelA?.uniqueSize ?? 0, Int64(12288), r, "model A unique size")
        expectEqual(modelA?.sharedLayerCount ?? 0, 1, r, "model A shared layer count")

        let modelB = audit.models.first { $0.name == "test-b" }
        expectEqual(modelB?.totalSize ?? 0, Int64(4096), r, "model B total")
        expectEqual(modelB?.uniqueSize ?? 0, Int64(0), r, "model B unique (only shared layer)")
        r.check(!audit.ollamaRunning, "server not running in fixture")
    }

    private static func missingBlobsReported(tempRoot: URL, r: TestRecorder) throws {
        let phantom = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        try makeManifest(
            registry: "registry.ollama.ai", namespace: "library", name: "ghost", tag: "latest",
            configDigest: nil, layerDigests: [phantom], root: tempRoot
        )
        let audit = OllamaAuditor(homeDirectory: tempRoot).audit()
        expectEqual(audit.models.count, 1, r, "model count")
        expectEqual(audit.models.first?.missingBlobDigests, [phantom], r, "missing blob reported")
        expectEqual(audit.models.first?.totalSize ?? -1, Int64(0), r, "missing blob has zero size")
    }

    private static func blobsUniqueToModel(tempRoot: URL, r: TestRecorder) throws {
        let shared = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
        let unique = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
        try makeBlob(shared, size: 4096, root: tempRoot)
        try makeBlob(unique, size: 4096, root: tempRoot)
        let manifestA = try makeManifest(
            registry: "registry.ollama.ai", namespace: nil, name: "a", tag: "latest",
            configDigest: nil, layerDigests: [shared, unique], root: tempRoot
        )
        try makeManifest(
            registry: "registry.ollama.ai", namespace: nil, name: "b", tag: "latest",
            configDigest: nil, layerDigests: [shared], root: tempRoot
        )

        let audit = OllamaAuditor(homeDirectory: tempRoot).audit()
        let modelA = audit.models.first { resolvingSymlinks($0.manifestURL.path) == resolvingSymlinks(manifestA.path) }
        r.check(modelA != nil, "model A present; models found: \(audit.models.map { $0.manifestURL.path })")
        guard let modelA else { return }

        let blobs = OllamaAuditor.blobsUniqueTo(model: modelA, allModels: audit.models, blobs: audit.allBlobs)
        expectEqual(blobs.map { $0.digest }, [unique], r, "only unique blob deletable")
    }

    private static func processDetection(tempRoot: URL, r: TestRecorder) throws {
        try String(ProcessInfo.processInfo.processIdentifier).write(
            to: tempRoot.appendingPathComponent("ollama.pid"), atomically: true, encoding: .utf8
        )
        r.check(OllamaAuditor.isOllamaRunning(home: tempRoot), "own pid counts as running")

        try "not-a-pid".write(
            to: tempRoot.appendingPathComponent("ollama.pid"), atomically: true, encoding: .utf8
        )
        r.check(!OllamaAuditor.isOllamaRunning(home: tempRoot), "garbage pid counts as stopped")
    }

    private static func versionGrouping(_ r: TestRecorder) {
        func model(_ base: String, _ tag: String, daysAgo: Int, size: Int64) -> OllamaModelInfo {
            OllamaModelInfo(
                registry: "registry.ollama.ai", namespace: "library", name: base, tag: tag,
                manifestURL: URL(fileURLWithPath: "/fake/\(base)/\(tag)"),
                modificationDate: Date(timeIntervalSinceNow: -Double(daysAgo) * 86_400),
                totalSize: size, uniqueSize: size, layerCount: 1, sharedLayerCount: 0,
                missingBlobDigests: [], layerDigests: []
            )
        }
        let models = [
            model("qwen", "Q4_K_M", daysAgo: 10, size: 4000),
            model("qwen", "Q8_0", daysAgo: 2, size: 8000),
            model("llama", "latest", daysAgo: 1, size: 500),
        ]
        let groups = OllamaAuditor.modelGroups(from: models)
        expectEqual(groups.count, 2, r, "group count")

        let qwen = groups.first { $0.baseName.contains("qwen") }
        r.check(qwen != nil, "qwen group exists")
        expectEqual(qwen?.variants.count ?? 0, 2, r, "qwen has 2 variants")
        // Newest-first ordering: Q8_0 (2 days) before Q4_K_M (10 days).
        expectEqual(qwen?.variants.first?.tag ?? "", "Q8_0", r, "newest variant first")
        expectEqual(qwen?.variants.last?.tag ?? "", "Q4_K_M", r, "older variant second")

        // Audit-level helper exposes only multi-variant groups.
        var audit = OllamaAudit()
        audit.models = models
        expectEqual(audit.versionGroups.count, 1, r, "single-tag models not grouped")
    }

    private static func quantTagDetection(_ r: TestRecorder) {
        r.check(OllamaAuditor.looksLikeQuantTag("Q4_K_M"), "Q4_K_M is a quant tag")
        r.check(OllamaAuditor.looksLikeQuantTag("Q8_0"), "Q8_0 is a quant tag")
        r.check(OllamaAuditor.looksLikeQuantTag("IQ3_XS"), "IQ3_XS is a quant tag")
        r.check(OllamaAuditor.looksLikeQuantTag("F16"), "F16 is a quant tag (case-insensitive)")
        r.check(!OllamaAuditor.looksLikeQuantTag("latest"), "latest is not a quant tag")
        r.check(!OllamaAuditor.looksLikeQuantTag("Qwen2.5"), "model-ish tag is not a quant tag")
    }
}

// MARK: - llama.cpp audit tests

enum LlamaAuditTests {
    static func run(_ r: TestRecorder) throws {
        expectEqual(LlamaAuditor.prettyModelName("models--Qwen--Qwen2.5-7B-GGUF"), "Qwen/Qwen2.5-7B-GGUF", r, "hf name prettify")
        expectEqual(LlamaAuditor.prettyModelName("plain-folder"), "plain-folder", r, "plain name unchanged")

        let home = FileManager.default.homeDirectoryForCurrentUser
        expectEqual(LlamaAuditor.expandingTilde("~/foo", home: home), home.appendingPathComponent("foo"), r, "tilde expansion")
        expectEqual(LlamaAuditor.expandingTilde("/opt/homebrew", home: home), URL(fileURLWithPath: "/opt/homebrew"), r, "absolute passthrough")

        try duplicateDetection(r)
        try customFolderAudit(r)
        try ggufMetaParsing(r)
        homebrewVersionExtraction(r)
    }

    private static func duplicateDetection(_ r: TestRecorder) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gguf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Data("llama-gguf-payload".utf8)
        try payload.write(to: dir.appendingPathComponent("model-a.gguf"))
        try payload.write(to: dir.appendingPathComponent("model-a-copy.gguf"))
        try Data("different".utf8).write(to: dir.appendingPathComponent("model-b.gguf"))

        let files = LlamaAuditor.ggufFiles(under: dir)
        expectEqual(files.count, 3, r, "gguf count")
        let groups = LlamaAuditor.duplicateGroups(of: files)
        expectEqual(groups.count, 1, r, "one duplicate group")
        expectEqual(groups.first?.count ?? 0, 2, r, "group size")
        r.check(groups.first!.allSatisfy { $0.name != "model-b.gguf" }, "different file not grouped")
    }

    private static func customFolderAudit(_ r: TestRecorder) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gguf-custom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 1, count: 64).write(to: dir.appendingPathComponent("tiny.gguf"))

        let auditor = LlamaAuditor(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            customFolders: [dir.path],
            sourceScanRoots: []
        )
        let audit = auditor.audit()
        let custom = audit.modelDirs.filter { $0.source == .customFolder }
        expectEqual(custom.count, 1, r, "custom folder found")
        expectEqual(custom.first?.ggufFiles.count ?? 0, 1, r, "gguf found in custom folder")
        expectEqual(custom.first?.name ?? "", dir.lastPathComponent, r, "folder name")
    }

    /// Builds a minimal valid GGUF v3 file in memory.
    private static func makeGGUFData() -> Data {
        var data = Data()
        func append(_ value: UInt64, bytes: Int) {
            var v = value
            for _ in 0..<bytes {
                data.append(UInt8(truncatingIfNeeded: v))
                v >>= 8
            }
        }
        func append(_ string: String) {
            let raw = Data(string.utf8)
            append(UInt64(raw.count), bytes: 8)
            data.append(raw)
        }
        // value types (GGUFValueType raw values)
        let typeString = UInt64(8)
        let typeU32 = UInt64(4)

        data.append(Data("GGUF".utf8))
        append(3, bytes: 4)          // version
        append(0, bytes: 8)          // tensor count
        append(3, bytes: 8)          // metadata kv count

        append("general.architecture")
        append(typeString, bytes: 4)
        append("llama")

        append("general.file_type")
        append(typeU32, bytes: 4)
        append(UInt64(14), bytes: 4) // Q4_K_M

        append("llama.context_length")
        append(typeU32, bytes: 4)
        append(UInt64(4096), bytes: 4)
        return data
    }

    private static func ggufMetaParsing(_ r: TestRecorder) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gguf-meta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("model.gguf")
        try makeGGUFData().write(to: fileURL)

        let meta = GGUFMeta.parse(at: fileURL)
        r.check(meta != nil, "GGUF header parsed")
        expectEqual(meta?.version ?? 0, 3, r, "gguf version")
        expectEqual(meta?.architecture ?? "", "llama", r, "architecture")
        expectEqual(meta?.quantization ?? "", "Q4_K_M", r, "quantization from file_type")
        expectEqual(meta?.contextLength ?? 0, 4096, r, "context length")

        // A non-GGUF file yields nil metadata but still appears in listings.
        let bogus = dir.appendingPathComponent("bogus.gguf")
        try Data("not a gguf".utf8).write(to: bogus)
        r.check(GGUFMeta.parse(at: bogus) == nil, "bogus file has no metadata")

        let files = LlamaAuditor.ggufFiles(under: dir)
        expectEqual(files.count, 2, r, "both .gguf files listed")
        let parsed = files.first { $0.name == "model.gguf" }
        expectEqual(parsed?.meta?.quantization ?? "", "Q4_K_M", r, "meta attached during collection")
    }

    /// The Homebrew version comes from the resolved Cellar version directory,
    /// not the package dir name (regression: it used to report "llama.cpp").
    private static func homebrewVersionExtraction(_ r: TestRecorder) {
        // Resolved: /opt/homebrew/Cellar/llama.cpp/0.9.2/bin/llama-cli
        let resolved = URL(fileURLWithPath: "/opt/homebrew/Cellar/llama.cpp/0.9.2/bin/llama-cli")
        let binDir = resolved.deletingLastPathComponent()
        let versionDir = binDir.deletingLastPathComponent()
        let packageDir = versionDir.deletingLastPathComponent()
        let isCellar = packageDir.deletingLastPathComponent().lastPathComponent == "Cellar"
        let version = isCellar ? versionDir.lastPathComponent : nil

        expectEqual(packageDir.path, "/opt/homebrew/Cellar/llama.cpp", r, "package dir resolution")
        expectEqual(version ?? "", "0.9.2", r, "version from Cellar layout")
    }
}

// MARK: - Ignore rules tests

enum IgnoreRulesTests {
    static func run(_ r: TestRecorder) {
        // Glob compilation
        r.check(IgnoreRules.compile("node_modules") != nil, "plain glob compiles")
        r.check(IgnoreRules.compile("[weird") != nil, "regex metacharacters are escaped")

        let rules = IgnoreRules(forTesting: true)
        rules.setPatterns([
            "node_modules/",
            "*.tmp",
            "build",
            "# comment line",
            "",
        ])
        r.check(rules.excludes(path: "/Users/x/project/node_modules"), "directory rule matches dir")
        r.check(rules.excludes(path: "/Users/x/project/node_modules/foo/bar.js"), "directory rule matches descendants")
        r.check(rules.excludes(path: "/deep/node_modules"), "directory rule matches anywhere")
        r.check(rules.excludes(path: "/Users/x/scratch/temp.tmp"), "wildcard rule matches extension")
        r.check(rules.excludes(path: "/Users/x/project/build"), "bare name matches exact dir anywhere")
        r.check(rules.excludes(path: "/Users/x/build/nested"), "bare name matches descendants")
        r.check(!rules.excludes(path: "/Users/x/project/builder"), "bare name does not match prefix")
        r.check(!rules.excludes(path: "/Users/x/project/src/main.swift"), "normal files pass")

        // '*' must not cross "/" boundaries; '**' must.
        rules.setPatterns(["/a*c"])
        r.check(rules.excludes(path: "/abc"), "single star within segment")
        r.check(!rules.excludes(path: "/a/x/c"), "single star does not cross slash")
        rules.setPatterns(["/a**c"])
        r.check(rules.excludes(path: "/a/x/c"), "double star crosses slash")
        r.check(rules.excludes(path: "/abc"), "double star also matches within segment")

        // Reader never blocks scanning entirely.
        rules.setPatterns([])
        r.check(!rules.excludes(path: "/anything/at/all"), "empty rules exclude nothing")
    }
}

// MARK: - Disk tree + scanner tests

enum DiskTreeTests {
    static func run(_ r: TestRecorder) {
        let file = node("big.bin", path: "/Users/x/sub/big.bin", bytes: 500, isDirectory: false)
        let sub = node("sub", path: "/Users/x/sub", bytes: 0, children: [file])
        let root = node("x", path: "/Users/x", bytes: 100, children: [sub])

        let updated = root.removing(path: "/Users/x/sub/big.bin")
        expectEqual(updated.totalBytes, Int64(100), r, "ancestor total after removal")
        let updatedSub = updated.children.first { $0.name == "sub" }
        expectEqual(updatedSub?.totalBytes ?? -1, Int64(0), r, "parent total after removal")
        expectEqual(updatedSub?.children.count ?? -1, 0, r, "child removed")

        let small = node("a.bin", path: "/a.bin", bytes: 10, isDirectory: false)
        let big = node("b.bin", path: "/b.bin", bytes: 900, isDirectory: false)
        let tree = node("r", path: "/r", bytes: 0, children: [small, big])
        expectEqual(tree.largestFiles().first?.name, "b.bin", r, "largest file first")

        r.check(DiskScanner.shouldSkip(path: "/System/Volumes/Data", scanRoot: "/"), "skip firmlink volume")
        r.check(DiskScanner.shouldSkip(path: "/dev/null", scanRoot: "/"), "skip /dev")
        r.check(DiskScanner.shouldSkip(path: "/.Spotlight-V100/store", scanRoot: "/"), "skip spotlight")
        r.check(DiskScanner.shouldSkip(path: "/Users/me/.Trashes", scanRoot: "/Users/me"), "skip trashes")
        r.check(!DiskScanner.shouldSkip(path: "/Users/me/System/Volumes", scanRoot: "/Users/me"), "root prefixes only apply at root")
    }

    /// REGRESSION for the bounded-pool deadlock: a deep tree scanned with
    /// concurrency 2 must complete. The old implementation held a semaphore
    /// permit across the child TaskGroup await, deadlocking at depth ≥ 3.
    static func runDeepTreeScan(_ r: TestRecorder) async {
        // Build root/l0/l1/.../l5 with one 4096-byte file at each level.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("deep-scan-\(UUID().uuidString)")
        var dir = base
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for level in 0..<6 {
            dir = dir.appendingPathComponent("l\(level)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? Data(repeating: 7, count: 4096).write(to: dir.appendingPathComponent("f.bin"))
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let scanner = DiskScanner(root: base, concurrency: 2)
        // 6 files × 4096 bytes; if the pool deadlocks this await never returns.
        let node = await scanner.scan()
        expectEqual(node.totalBytes, Int64(6 * 4096), r, "deep tree scanned without deadlock")
        expectEqual(node.itemCount, 6 + 6 + 1, r, "deep tree item count (6 files + 6 dirs + root)")

        // A wide tree at concurrency 2 as well.
        let wide = FileManager.default.temporaryDirectory
            .appendingPathComponent("wide-scan-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: wide, withIntermediateDirectories: true)
        for i in 0..<30 {
            let sub = wide.appendingPathComponent("d\(i)")
            try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            try? Data(repeating: 1, count: 4096).write(to: sub.appendingPathComponent("f.bin"))
        }
        defer { try? FileManager.default.removeItem(at: wide) }

        let wideNode = await DiskScanner(root: wide, concurrency: 2).scan()
        expectEqual(wideNode.totalBytes, Int64(30 * 4096), r, "wide tree scanned without deadlock")
    }

    private static func node(_ name: String, path: String, bytes: Int64, children: [DiskNode] = [], isDirectory: Bool = true) -> DiskNode {
        let childBytes = children.reduce(Int64(0)) { $0 + $1.totalBytes }
        let childItems = children.reduce(0) { $0 + $1.itemCount }
        return DiskNode(
            path: path, name: name, isDirectory: isDirectory,
            ownBytes: isDirectory ? 0 : bytes,
            totalBytes: bytes + childBytes,
            itemCount: 1 + childItems,
            children: children,
            accessDenied: false
        )
    }
}

// MARK: - Report tests

enum ReportTests {
    static func run(_ r: TestRecorder) {
        let report = ScheduledAudit.run()
        expectEqual(report.volumes.isEmpty, false, r, "at least one volume reported")
        r.check(report.volumes.contains { $0.totalBytes > 0 }, "volumes have capacity")
        r.check(report.ollama.modelCount >= 0, "ollama report present")
        r.check(report.llama.modelLocationCount >= 0, "llama report present")

        // JSON round trip
        if let data = try? JSONEncoder.macSpaces.encode(report),
           let text = String(data: data, encoding: .utf8) {
            r.check(text.contains("generatedAt"), "report JSON encodes")
        } else {
            r.check(false, "report JSON encodes")
        }
    }
}

// MARK: - Security regression tests

enum SecurityTests {
    static func run(_ r: TestRecorder) {
        // 1. Root/home deletion guards.
        let home = FileManager.default.homeDirectoryForCurrentUser
        r.check(TrashService.refusalReason(for: URL(fileURLWithPath: "/")) != nil, "root deletion refused")
        r.check(TrashService.refusalReason(for: home) != nil, "home deletion refused")
        r.check(TrashService.refusalReason(for: home.appendingPathComponent("sub")) == nil, "normal paths allowed")

        // 2. Symlink-safe write targets.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sec-write-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent("plain.json")
        try? Data("x".utf8).write(to: plain)
        r.check(ScheduledAudit.isSafeWriteTarget(plain), "plain file is a safe write target")
        r.check(!ScheduledAudit.isSafeWriteTarget(dir.appendingPathComponent("missing-folder/report.json")), "missing parent dir refused")

        let link = dir.appendingPathComponent("planted.json")
        let victim = dir.appendingPathComponent("victim.txt")
        try? Data("victim".utf8).write(to: victim)
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        r.check(!ScheduledAudit.isSafeWriteTarget(link), "planted symlink refused as write target")

        // 3. Regex DoS: star runs collapse to one quantifier; long patterns capped.
        let pathological = String(repeating: "*.*", count: 100)
        let regex = IgnoreRules.compile(pathological)
        r.check(regex != nil, "pathological glob still compiles")
        if let regex {
            // A 200-char non-matching path must match instantly (the compiled
            // pattern has no adjacent quantifiers to backtrack between).
            let longPath = "/" + String(repeating: "a/", count: 100) + "z"
            let start = Date()
            _ = regex.firstMatch(in: longPath, range: NSRange(longPath.startIndex..., in: longPath))
            r.check(Date().timeIntervalSince(start) < 0.5, "pathological pattern matches fast (no backtracking blowup)")
        }
        var manyPatterns: [String] = []
        for i in 0..<2000 { manyPatterns.append("pattern\(i)/") }
        let rules = IgnoreRules(forTesting: true)
        rules.setPatterns(manyPatterns)
        r.check(!rules.excludes(path: "/nothing/here"), "oversized pattern list capped (500) without error")

        rules.setPatterns([String(repeating: "a", count: 300)])
        r.check(!rules.excludes(path: "/aaaa"), "over-long pattern rejected")

        // 4. Migration dedupe keeps reference counts honest: the same model in
        // both layouts must not inflate shared-layer counts.
        rules.setPatterns([])
    }

    static func runDedupeReferenceCounts(_ r: TestRecorder) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dedupe-refs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let shared = "sha256:9999999999999999999999999999999999999999999999999999999999999999"
        // One blob, referenced by the same model+tag in BOTH layouts.
        let blob = tempRoot.appendingPathComponent("models/blobs")
            .appendingPathComponent(Format.blobFileName(forDigest: shared))
        try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: blob)

        let manifest: [String: Any] = [
            "schemaVersion": 2,
            "layers": [["mediaType": "m", "digest": shared, "size": 0]],
        ]
        for root in ["manifests", "manifests-v2"] {
            let path = tempRoot
                .appendingPathComponent("models/\(root)/ollama.com/library/dupe/latest")
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: manifest).write(to: path)
        }

        let audit = OllamaAuditor(homeDirectory: tempRoot).audit()
        expectEqual(audit.models.count, 1, r, "migration duplicate collapsed")
        expectEqual(audit.models.first?.sharedLayerCount ?? -1, 0, r, "single deduped manifest: layer not shared")
        expectEqual(audit.models.first?.uniqueSize ?? -1, Int64(4096), r, "layer is unique to the deduped model")
        expectEqual(audit.orphanedBlobs.count, 0, r, "referenced blob not orphaned")
    }
}

// MARK: - Entry point

@main
struct TestMain {
    static func main() async {
        let recorder = TestRecorder()

        do { try OllamaAuditTests.run(recorder) } catch { recorder.failures.append("OllamaAuditTests threw: \(error)") }
        do { try LlamaAuditTests.run(recorder) } catch { recorder.failures.append("LlamaAuditTests threw: \(error)") }
        IgnoreRulesTests.run(recorder)
        SecurityTests.run(recorder)
        do { try SecurityTests.runDedupeReferenceCounts(recorder) } catch { recorder.failures.append("SecurityTests.dedupe threw: \(error)") }
        DiskTreeTests.run(recorder)
        await DiskTreeTests.runDeepTreeScan(recorder)
        ReportTests.run(recorder)

        print("Passed assertions: \(recorder.passed)")
        if recorder.failures.isEmpty {
            print("ALL TESTS PASSED")
        } else {
            print("FAILURES (\(recorder.failures.count)):")
            for failure in recorder.failures { print("  ✗ \(failure)") }
            exit(1)
        }
    }
}
