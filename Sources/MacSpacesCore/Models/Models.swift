import Foundation

// MARK: - Volumes

public struct VolumeInfo: Identifiable, Hashable {
    public let url: URL
    public let name: String
    public let totalCapacity: Int64
    public let availableCapacity: Int64

    public var id: String { url.path }
    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    public var usedFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    public init(url: URL, name: String, totalCapacity: Int64, availableCapacity: Int64) {
        self.url = url
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }
}

// MARK: - Disk tree

public struct DiskNode: Identifiable, Hashable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    /// Bytes occupied by files directly inside this node (not recursive).
    public var ownBytes: Int64
    /// Bytes occupied by everything below this node, inclusive.
    public var totalBytes: Int64
    /// Number of entries (files + folders) below this node, inclusive of itself.
    public var itemCount: Int
    public var children: [DiskNode]
    public var accessDenied: Bool

    public init(
        path: String, name: String, isDirectory: Bool, ownBytes: Int64, totalBytes: Int64,
        itemCount: Int, children: [DiskNode], accessDenied: Bool
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.ownBytes = ownBytes
        self.totalBytes = totalBytes
        self.itemCount = itemCount
        self.children = children
        self.accessDenied = accessDenied
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
    public static func == (lhs: DiskNode, rhs: DiskNode) -> Bool { lhs.path == rhs.path }

    /// Largest files anywhere below this node, sorted by size descending.
    public func largestFiles(limit: Int = 100) -> [DiskNode] {
        var files: [DiskNode] = []
        var stack: [DiskNode] = [self]
        while !stack.isEmpty {
            let node = stack.removeLast()
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else {
                files.append(node)
            }
        }
        return Array(files.sorted { $0.totalBytes > $1.totalBytes }.prefix(limit))
    }

    /// Returns a copy of the tree with the node at `path` removed,
    /// subtracting its size from every ancestor along the way.
    public func removing(path: String) -> DiskNode {
        var copy = self
        guard copy.isDirectory else { return copy }
        var newChildren: [DiskNode] = []
        var removedBytes: Int64 = 0
        var removedItems = 0
        for child in copy.children {
            if child.path == path {
                removedBytes = child.totalBytes
                removedItems = child.itemCount
            } else if path.hasPrefix(child.path + "/") {
                let updated = child.removing(path: path)
                removedBytes = child.totalBytes - updated.totalBytes
                removedItems = child.itemCount - updated.itemCount
                newChildren.append(updated)
            } else {
                newChildren.append(child)
            }
        }
        copy.children = newChildren
        copy.totalBytes = max(copy.ownBytes, copy.totalBytes - removedBytes)
        copy.itemCount = max(1, copy.itemCount - removedItems)
        return copy
    }
}

// MARK: - Ollama

public struct BlobInfo: Identifiable, Hashable {
    public let digest: String
    public let url: URL
    public let size: Int64

    public var id: String { digest }
    public var fileName: String { url.lastPathComponent }

    public init(digest: String, url: URL, size: Int64) {
        self.digest = digest
        self.url = url
        self.size = size
    }
}

public struct OllamaModelInfo: Identifiable, Hashable {
    public let registry: String
    public let namespace: String
    public let name: String
    public let tag: String
    public let manifestURL: URL
    /// Sum of every blob the manifest references (shared layers counted in full).
    public let totalSize: Int64
    /// Sum of blobs referenced only by this manifest.
    public let uniqueSize: Int64
    public let layerCount: Int
    public let sharedLayerCount: Int
    public let missingBlobDigests: [String]
    /// Digests referenced by this manifest (config + layers).
    public let layerDigests: [String]

    public var id: String { manifestURL.path }
    public var qualifiedName: String {
        let prefix = namespace.isEmpty ? "" : "\(namespace)/"
        return "\(registry)/\(prefix)\(name):\(tag)"
    }

    public init(
        registry: String, namespace: String, name: String, tag: String, manifestURL: URL,
        totalSize: Int64, uniqueSize: Int64, layerCount: Int, sharedLayerCount: Int,
        missingBlobDigests: [String], layerDigests: [String]
    ) {
        self.registry = registry
        self.namespace = namespace
        self.name = name
        self.tag = tag
        self.manifestURL = manifestURL
        self.totalSize = totalSize
        self.uniqueSize = uniqueSize
        self.layerCount = layerCount
        self.sharedLayerCount = sharedLayerCount
        self.missingBlobDigests = missingBlobDigests
        self.layerDigests = layerDigests
    }
}

public struct FootprintItem: Identifiable, Hashable {
    public let name: String
    public let url: URL
    public let size: Int64
    public var id: String { url.path }

    public init(name: String, url: URL, size: Int64) {
        self.name = name
        self.url = url
        self.size = size
    }
}

public struct OllamaAudit {
    public var models: [OllamaModelInfo] = []
    public var allBlobs: [BlobInfo] = []
    public var orphanedBlobs: [BlobInfo] = []
    /// Blobs shared by two or more manifests.
    public var sharedBlobDigests: Set<String> = []
    public var modelsRootSize: Int64 = 0
    public var footprint: [FootprintItem] = []
    public var ollamaHome: URL?
    public var ollamaRunning: Bool = false
    public var warnings: [String] = []

    public init() {}

    public var orphanedBytes: Int64 { orphanedBlobs.reduce(0) { $0 + $1.size } }
    public var modelsBytes: Int64 { models.reduce(0) { $0 + $1.totalSize } }
}

// MARK: - llama.cpp

public enum LlamaInstallKind: String, Hashable {
    case homebrew
    case source
}

public struct LlamaInstall: Identifiable, Hashable {
    public let kind: LlamaInstallKind
    public let name: String
    public let path: String
    public let version: String?
    public let totalBytes: Int64
    public let buildBytes: Int64
    public let executables: [String]

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(
        kind: LlamaInstallKind, name: String, path: String, version: String?,
        totalBytes: Int64, buildBytes: Int64, executables: [String]
    ) {
        self.kind = kind
        self.name = name
        self.path = path
        self.version = version
        self.totalBytes = totalBytes
        self.buildBytes = buildBytes
        self.executables = executables
    }
}

public enum ModelSource: String, Hashable, CaseIterable {
    case llamaCache = "llama.cpp cache"
    case huggingFace = "HuggingFace cache"
    case customFolder = "Custom folder"
}

public struct GGUFFile: Identifiable, Hashable {
    public let path: String
    public let size: Int64
    /// Cheap content fingerprint (size + head/tail bytes) used to spot duplicates.
    public let fingerprint: String

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }

    public init(path: String, size: Int64, fingerprint: String) {
        self.path = path
        self.size = size
        self.fingerprint = fingerprint
    }
}

public struct ModelDirInfo: Identifiable, Hashable {
    public let source: ModelSource
    public let name: String
    public let path: String
    public let totalBytes: Int64
    public let ggufFiles: [GGUFFile]

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(
        source: ModelSource, name: String, path: String, totalBytes: Int64, ggufFiles: [GGUFFile]
    ) {
        self.source = source
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.ggufFiles = ggufFiles
    }
}

public struct LlamaAudit {
    public var installs: [LlamaInstall] = []
    public var modelDirs: [ModelDirInfo] = []
    public var duplicateGroups: [[GGUFFile]] = []
    public var scannedRoots: [String] = []
    public var warnings: [String] = []

    public init() {}

    public var ggufBytes: Int64 {
        modelDirs.reduce(0) { $0 + $1.totalBytes }
    }
    public var duplicateReclaimableBytes: Int64 {
        duplicateGroups.reduce(0) { total, group in
            guard group.count > 1 else { return total }
            // Keep the first copy, reclaim the rest.
            return total + group.dropFirst().reduce(0) { $0 + $1.size }
        }
    }
}

// MARK: - Scan progress

public struct ScanProgress: Equatable {
    public var phase: String = "Preparing"
    public var currentItem: String = ""
    public var scannedItems: Int = 0
    public var scannedBytes: Int64 = 0

    public init() {}

    public static let empty = ScanProgress()
}

// MARK: - Deletion

public enum DeletionMode: String, CaseIterable, Identifiable {
    case trash = "Move to Trash"
    case permanent = "Delete Permanently"

    public var id: String { rawValue }
}

public struct DeleteOutcome: Identifiable {
    public let url: URL
    public let success: Bool
    public let message: String?
    public var id: String { url.path }

    public init(url: URL, success: Bool, message: String?) {
        self.url = url
        self.success = success
        self.message = message
    }
}

// MARK: - Formatting helpers

public enum Format {
    public static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    public static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    /// "sha256:abc123…" → "sha256-abc123…" (Ollama blob file naming).
    public static func blobFileName(forDigest digest: String) -> String {
        digest.replacingOccurrences(of: ":", with: "-")
    }

    /// "sha256-abc123…" → "sha256:abc123…"
    public static func digest(forBlobFileName name: String) -> String {
        name.replacingOccurrences(of: "-", with: ":")
    }
}
