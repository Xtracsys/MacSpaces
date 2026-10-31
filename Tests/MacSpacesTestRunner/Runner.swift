import Foundation
@testable import MacSpacesCore

private func resolvingSymlinks(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

// Macro-free test harness: CLT on this machine ships neither the XCTest
// framework nor the Swift Testing macro plugin, so tests are plain code.

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

// MARK: - Ollama audit tests

enum OllamaAuditTests {
    static func run(_ r: TestRecorder) throws {
        try digestRoundTrip(r)
        try withTempRoot { try orphanDetectionAndSharedLayers(tempRoot: $0, r: r) }
        try withTempRoot { try missingBlobsReported(tempRoot: $0, r: r) }
        try withTempRoot { try blobsUniqueToModel(tempRoot: $0, r: r) }
        try withTempRoot { try processDetection(tempRoot: $0, r: r) }
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
}

// MARK: - Disk tree tests

enum DiskTreeTests {
    static func run(_ r: TestRecorder) async {
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

        do {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("disk-scanner-deadlock-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: base) }
            var current = base
            for index in 0..<20 {
                current = current.appendingPathComponent("level-\(index)")
                try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
            }
            try Data(repeating: 0xAB, count: 4096).write(to: current.appendingPathComponent("leaf.bin"))
            let scanned = await DiskScanner(root: base, concurrency: 1).scan()
            r.check(scanned.totalBytes >= 4096, "nested scan completes with one permit")
        } catch {
            r.failures.append("DiskTreeTests nested scan threw: \(error)")
        }
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

// MARK: - Entry point

@main
struct TestMain {
    static func main() async {
        let recorder = TestRecorder()

        do { try OllamaAuditTests.run(recorder) } catch { recorder.failures.append("OllamaAuditTests threw: \(error)") }
        do { try LlamaAuditTests.run(recorder) } catch { recorder.failures.append("LlamaAuditTests threw: \(error)") }
        await DiskTreeTests.run(recorder)

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
