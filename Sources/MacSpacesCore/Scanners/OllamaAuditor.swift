import Foundation

/// Audits the local Ollama installation: parses model manifests, detects
/// orphaned blobs, reports the on-disk footprint of `~/.ollama`.
public struct OllamaAuditor {
    struct ManifestBlob: Decodable {
        let mediaType: String?
        let digest: String?
        let size: Int64?
    }

    struct ManifestDocument: Decodable {
        let schemaVersion: Int?
        let mediaType: String?
        let config: ManifestBlob?
        let layers: [ManifestBlob]?
    }

    public let homeDirectory: URL
    /// Ollama's model store root (`~/.ollama/models` by default).
    public var modelsRoot: URL { homeDirectory.appendingPathComponent("models") }

    /// Ollama 0.34+ is migrating to `manifests-v2/`; both trees are scanned and
    /// duplicates (same registry/ns/name/tag) resolved in favor of v2.
    public var manifestRoots: [URL] {
        ["manifests", "manifests-v2"].map { modelsRoot.appendingPathComponent($0) }
    }

    public init(homeDirectory: URL? = nil) {
        if let homeDirectory {
            self.homeDirectory = homeDirectory
        } else {
            self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ollama")
        }
    }

    // MARK: - Public API

    public func audit() -> OllamaAudit {
        var audit = OllamaAudit()
        audit.ollamaHome = homeDirectory
        audit.ollamaRunning = Self.isOllamaRunning(home: homeDirectory)

        guard FileManager.default.fileExists(atPath: modelsRoot.path) else {
            audit.warnings.append("No Ollama models directory found at \(modelsRoot.path).")
            return audit
        }

        let manifests = manifestFiles()
        let blobs = blobFiles()
        audit.allBlobs = blobs

        var blobByDigest: [String: BlobInfo] = [:]
        for blob in blobs { blobByDigest[blob.digest] = blob }

        for manifestURL in manifests {
            if let info = parseManifest(at: manifestURL, blobLookup: blobByDigest) {
                audit.models.append(info)
            }
        }

        // Migration duplicates (same model+tag in manifests/ and manifests-v2/):
        // dedupe FIRST, then count references — otherwise both copies of a
        // model inflate reference counts and shared-layer attribution.
        audit.models = Self.dedupeMigrationDuplicates(audit.models)

        // digest → number of distinct (deduped) manifests referencing it
        var referenceCounts: [String: Int] = [:]
        for model in audit.models {
            for digest in Set(model.layerDigests) {
                referenceCounts[digest, default: 0] += 1
            }
        }

        audit.models.sort { $0.totalSize > $1.totalSize }

        // Attribute shared layers now that references are counted over the
        // deduped model list.
        var modelsWithSharing: [OllamaModelInfo] = []
        for model in audit.models {
            let digestSet = Set(model.layerDigests)
            let shared = digestSet.filter { (referenceCounts[$0] ?? 0) > 1 }
            let uniqueDigests = digestSet.filter { (referenceCounts[$0] ?? 0) == 1 }
            var uniqueSize: Int64 = 0
            for digest in uniqueDigests { uniqueSize += blobByDigest[digest]?.size ?? 0 }
            modelsWithSharing.append(OllamaModelInfo(
                registry: model.registry, namespace: model.namespace, name: model.name,
                tag: model.tag, manifestURL: model.manifestURL,
                modificationDate: model.modificationDate,
                totalSize: model.totalSize, uniqueSize: uniqueSize,
                layerCount: model.layerCount, sharedLayerCount: shared.count,
                missingBlobDigests: model.missingBlobDigests, layerDigests: model.layerDigests
            ))
        }
        audit.models = modelsWithSharing

        audit.sharedBlobDigests = Set(referenceCounts.filter { $0.value > 1 }.keys)
        audit.orphanedBlobs = blobs
            .filter { (referenceCounts[$0.digest] ?? 0) == 0 }
            .sorted { $0.size > $1.size }

        audit.modelsRootSize = DiskScanner.sequentialSize(of: modelsRoot)
        audit.footprint = footprint()
        return audit
    }

    // MARK: - Manifest discovery & parsing

    public func manifestFiles() -> [URL] {
        var files: [URL] = []
        for root in manifestRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { continue }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name == ".DS_Store" { continue }
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir { files.append(url) }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Keeps one entry per model+tag; when the same model exists in both
    /// manifests/ and manifests-v2/, the v2 manifest wins.
    static func dedupeMigrationDuplicates(_ models: [OllamaModelInfo]) -> [OllamaModelInfo] {
        var best: [String: OllamaModelInfo] = [:]
        for model in models {
            let key = model.qualifiedName
            if let existing = best[key] {
                let existingIsV2 = existing.manifestURL.path.contains("manifests-v2")
                let candidateIsV2 = model.manifestURL.path.contains("manifests-v2")
                if candidateIsV2 && !existingIsV2 { best[key] = model }
            } else {
                best[key] = model
            }
        }
        return Array(best.values)
    }

    private func parseManifest(at url: URL, blobLookup: [String: BlobInfo]) -> OllamaModelInfo? {
        // Path layout: models/manifests[/‑v2]/<registry>/<namespace…>/<name>/<tag>
        let components = url.pathComponents
        let manifestsIndex = components.lastIndex { $0 == "manifests" || $0.hasPrefix("manifests-") }
        guard let manifestsIndex else { return nil }
        let rest = Array(components[(manifestsIndex + 1)...])
        guard rest.count >= 2 else { return nil }
        let tag = rest.last!
        let name = rest[rest.count - 2]
        let registry = rest.first!
        let namespace = rest.count > 2 ? rest[1..<(rest.count - 2)].joined(separator: "/") : ""

        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(ManifestDocument.self, from: data)
        else { return nil }

        var digests: [String] = []
        if let digest = document.config?.digest { digests.append(digest) }
        for layer in document.layers ?? [] {
            if let digest = layer.digest { digests.append(digest) }
        }

        var totalSize: Int64 = 0
        var missing: [String] = []
        for digest in digests {
            if let blob = blobLookup[digest] {
                totalSize += blob.size
            } else {
                missing.append(digest)
            }
        }

        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return OllamaModelInfo(
            registry: registry,
            namespace: namespace,
            name: name,
            tag: tag,
            manifestURL: url,
            modificationDate: modDate,
            totalSize: totalSize,
            uniqueSize: 0, // filled in by the audit post-pass
            layerCount: digests.count,
            sharedLayerCount: 0,
            missingBlobDigests: missing,
            layerDigests: digests
        )
    }

    // MARK: - Version grouping (feature: model version manager)

    /// Groups manifests by base name (everything before the tag), variants
    /// sorted newest-first by manifest modification date.
    public static func modelGroups(from models: [OllamaModelInfo]) -> [OllamaModelGroup] {
        var byBase: [String: [OllamaModelInfo]] = [:]
        for model in models { byBase[model.baseName, default: []].append(model) }
        return byBase
            .map { base, variants in
                OllamaModelGroup(
                    baseName: base,
                    variants: variants.sorted {
                        ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
                    }
                )
            }
            .sorted { $0.totalSize > $1.totalSize }
    }

    /// Heuristic: does this tag look like a quantization level (Q4_K_M, IQ3_XS, Q8_0, F16…)?
    public static func looksLikeQuantTag(_ tag: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: "^(iq\\d+|q\\d+|f16|f32|bf16)", options: [.caseInsensitive])
        guard let regex else { return false }
        let range = NSRange(tag.startIndex..., in: tag)
        return regex.firstMatch(in: tag, options: [], range: range) != nil
    }

    // MARK: - Blobs

    public func blobFiles() -> [BlobInfo] {
        let blobsRoot = modelsRoot.appendingPathComponent("blobs")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: blobsRoot, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey], options: []
        ) else { return [] }

        var blobs: [BlobInfo] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("sha256-") else { continue }
            let values = try? entry.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            blobs.append(BlobInfo(digest: Format.digest(forBlobFileName: name), url: entry, size: size))
        }
        return blobs
    }

    // MARK: - Footprint

    /// Sizes of every top-level directory under `~/.ollama`.
    public func footprint() -> [FootprintItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: homeDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }

        var items: [FootprintItem] = []
        for entry in entries where entry.lastPathComponent != ".DS_Store" {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = isDir ? DiskScanner.sequentialSize(of: entry) : ((try? entry.resourceValues(forKeys: [.totalFileAllocatedSizeKey])).map { Int64($0.totalFileAllocatedSize ?? 0) } ?? 0)
            items.append(FootprintItem(name: entry.lastPathComponent, url: entry, size: size))
        }
        return items.sorted { $0.size > $1.size }
    }

    // MARK: - Process detection

    /// True if an Ollama server process appears to be running for this install.
    /// kill(pid, 0) only probes existence — no signal is sent; EPERM (another
    /// user's process) correctly reports as not running.
    public static func isOllamaRunning(home: URL) -> Bool {
        let pidFile = home.appendingPathComponent("ollama.pid")
        guard let contents = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return kill(pid, 0) == 0
    }

    // MARK: - Deletion helpers

    /// Blobs referenced *only* by the given manifest (safe to delete with it).
    public static func blobsUniqueTo(model: OllamaModelInfo, allModels: [OllamaModelInfo], blobs: [BlobInfo]) -> [BlobInfo] {
        let referencedElsewhere = Set(
            allModels.filter { $0.id != model.id }.flatMap { referencedDigests(of: $0.manifestURL) }
        )
        let ownDigests = Set(referencedDigests(of: model.manifestURL))
        let deletable = ownDigests.subtracting(referencedElsewhere)
        return blobs.filter { deletable.contains($0.digest) }
    }

    public static func referencedDigests(of manifestURL: URL) -> [String] {
        guard let data = try? Data(contentsOf: manifestURL),
              let document = try? JSONDecoder().decode(ManifestDocument.self, from: data)
        else { return [] }
        var digests: [String] = []
        if let digest = document.config?.digest { digests.append(digest) }
        for layer in document.layers ?? [] {
            if let digest = layer.digest { digests.append(digest) }
        }
        return digests
    }
}
