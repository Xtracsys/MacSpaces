import Foundation

/// Audits the local Ollama installation: parses model manifests, detects
/// orphaned blobs, reports the on-disk footprint of `~/.ollama`.
struct OllamaAuditor {
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

    let homeDirectory: URL
    /// Ollama's model store root (`~/.ollama/models` by default).
    var modelsRoot: URL { homeDirectory.appendingPathComponent("models") }

    init(homeDirectory: URL? = nil) {
        if let homeDirectory {
            self.homeDirectory = homeDirectory
        } else {
            self.homeDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ollama")
        }
    }

    // MARK: - Public API

    func audit() -> OllamaAudit {
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

        // digest → number of manifests referencing it
        var referenceCounts: [String: Int] = [:]

        for manifestURL in manifests {
            guard let info = parseManifest(at: manifestURL, blobLookup: blobByDigest) else { continue }
            audit.models.append(info)
            for digest in referencedDigests(of: manifestURL) {
                referenceCounts[digest, default: 0] += 1
            }
        }

        audit.models.sort { $0.totalSize > $1.totalSize }

        // Attribute shared layers now that every manifest has been parsed.
        var modelsWithSharing: [OllamaModelInfo] = []
        for model in audit.models {
            let digestSet = Set(model.layerDigests)
            let shared = digestSet.filter { (referenceCounts[$0] ?? 0) > 1 }
            let uniqueDigests = digestSet.filter { (referenceCounts[$0] ?? 0) == 1 }
            var uniqueSize: Int64 = 0
            for digest in uniqueDigests { uniqueSize += blobByDigest[digest]?.size ?? 0 }
            modelsWithSharing.append(OllamaModelInfo(
                registry: model.registry, namespace: model.namespace, name: model.name,
                tag: model.tag, manifestURL: model.manifestURL, totalSize: model.totalSize,
                uniqueSize: uniqueSize, layerCount: model.layerCount,
                sharedLayerCount: shared.count, missingBlobDigests: model.missingBlobDigests,
                layerDigests: model.layerDigests
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

    func manifestFiles() -> [URL] {
        let manifestsRoot = modelsRoot.appendingPathComponent("manifests")
        guard let enumerator = FileManager.default.enumerator(
            at: manifestsRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".DS_Store" { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Digests (config + layers) referenced by the manifest at the given URL.
    func referencedDigests(of manifestURL: URL) -> [String] {
        Self.referencedDigests(of: manifestURL)
    }

    private func parseManifest(at url: URL, blobLookup: [String: BlobInfo]) -> OllamaModelInfo? {
        // Path layout: models/manifests/<registry>/<namespace…>/<name>/<tag>
        let components = url.pathComponents
        guard let manifestsIndex = components.lastIndex(of: "manifests") else { return nil }
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

        return OllamaModelInfo(
            registry: registry,
            namespace: namespace,
            name: name,
            tag: tag,
            manifestURL: url,
            totalSize: totalSize,
            uniqueSize: 0, // filled in by the audit post-pass
            layerCount: digests.count,
            sharedLayerCount: 0,
            missingBlobDigests: missing,
            layerDigests: digests
        )
    }

    // MARK: - Blobs

    func blobFiles() -> [BlobInfo] {
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
    func footprint() -> [FootprintItem] {
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
    static func isOllamaRunning(home: URL) -> Bool {
        let pidFile = home.appendingPathComponent("ollama.pid")
        guard let contents = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return kill(pid, 0) == 0
    }

    // MARK: - Deletion helpers

    /// Blobs referenced *only* by the given manifest (safe to delete with it).
    static func blobsUniqueTo(model: OllamaModelInfo, allModels: [OllamaModelInfo], blobs: [BlobInfo]) -> [BlobInfo] {
        let referencedElsewhere = Set(
            allModels.filter { $0.id != model.id }.flatMap { referencedDigests(of: $0.manifestURL) }
        )
        let ownDigests = Set(referencedDigests(of: model.manifestURL))
        let deletable = ownDigests.subtracting(referencedElsewhere)
        return blobs.filter { deletable.contains($0.digest) }
    }

    static func referencedDigests(of manifestURL: URL) -> [String] {
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
