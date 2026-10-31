import Foundation

/// Audits llama.cpp installations (Homebrew, source builds) and GGUF model
/// stores across runtimes: llama.cpp download cache, HuggingFace hub cache,
/// LM Studio, Jan, GPT4All, and user-configured custom folders.
public struct LlamaAuditor {
    public let homeDirectory: URL
    /// Folders scanned recursively for loose `*.gguf` files.
    public var customFolders: [String]
    /// Roots searched for source checkouts of llama.cpp.
    public var sourceScanRoots: [String]

    public static let defaultCustomFolders = ["~/.ollama/models/ggufs"]
    public static let defaultSourceRoots = ["~/llama.cpp", "~/src", "~/code", "~/Projects", "~/dev", "~/Developer"]

    public init(homeDirectory: URL? = nil, customFolders: [String]? = nil, sourceScanRoots: [String]? = nil) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.customFolders = customFolders ?? LlamaAuditor.defaultCustomFolders
        self.sourceScanRoots = sourceScanRoots ?? LlamaAuditor.defaultSourceRoots
    }

    // MARK: - Public API

    public func audit() -> LlamaAudit {
        var audit = LlamaAudit()
        audit.scannedRoots = sourceScanRoots

        audit.installs.append(contentsOf: homebrewInstalls())
        audit.installs.append(contentsOf: sourceInstalls())

        var modelDirs: [ModelDirInfo] = []
        modelDirs.append(contentsOf: llamaCacheModels())
        modelDirs.append(contentsOf: huggingFaceModels())
        modelDirs.append(contentsOf: lmStudioModels())
        modelDirs.append(contentsOf: janModels())
        modelDirs.append(contentsOf: gpt4AllModels())
        modelDirs.append(contentsOf: customFolderModels())
        audit.modelDirs = modelDirs.sorted { $0.totalBytes > $1.totalBytes }

        let allGGUFs = modelDirs.flatMap { $0.ggufFiles }
        audit.duplicateGroups = Self.duplicateGroups(of: allGGUFs)

        if audit.installs.isEmpty && audit.modelDirs.allSatisfy({ $0.ggufFiles.isEmpty && $0.totalBytes == 0 }) {
            audit.warnings.append("No llama.cpp installs or models found in the configured locations.")
        }
        return audit
    }

    // MARK: - Homebrew installs

    public func homebrewInstalls() -> [LlamaInstall] {
        var installs: [LlamaInstall] = []
        for prefix in ["/opt/homebrew", "/usr/local"] {
            let bin = URL(fileURLWithPath: "\(prefix)/bin")
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: bin, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
            ) else { continue }

            let llamaBinaries = entries.filter { $0.lastPathComponent.hasPrefix("llama-") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard !llamaBinaries.isEmpty else { continue }

            var executables: [String] = []
            // Cellar package dir → resolved version dir (same install may be
            // referenced by many bin symlinks; keep first).
            var packageInfo: (packageDir: URL, version: String?)?
            for binary in llamaBinaries {
                executables.append(binary.path)
                let resolved = binary.resolvingSymlinksInPath()
                // …/Cellar/llama.cpp/<version>/bin/llama-cli
                let binDir = resolved.deletingLastPathComponent()
                let versionDir = binDir.deletingLastPathComponent()
                let packageDir = versionDir.deletingLastPathComponent()
                guard packageDir.lastPathComponent.contains("llama.cpp"),
                      packageDir.deletingLastPathComponent().lastPathComponent == "Cellar"
                else { continue }
                if packageInfo == nil {
                    packageInfo = (packageDir, versionDir.lastPathComponent)
                }
            }

            guard let info = packageInfo else { continue }
            let total = DiskScanner.sequentialSize(of: info.packageDir)
            installs.append(LlamaInstall(
                kind: .homebrew,
                name: "llama.cpp (Homebrew)",
                path: info.packageDir.path,
                version: info.version,
                totalBytes: total,
                buildBytes: 0,
                executables: executables
            ))
        }
        return installs
    }

    // MARK: - Source builds

    public func sourceInstalls() -> [LlamaInstall] {
        var installs: [LlamaInstall] = []
        let fm = FileManager.default
        for rawRoot in sourceScanRoots {
            let root = Self.expandingTilde(rawRoot, home: homeDirectory)
            guard fm.fileExists(atPath: root.path) else { continue }

            // Walk up to depth 3 looking for directories that look like llama.cpp checkouts.
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            var visited: Set<String> = []
            for case let url as URL in enumerator {
                if (enumerator.level as Int) > 3 { enumerator.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                guard url.lastPathComponent.contains("llama.cpp") else { continue }
                guard !visited.contains(url.path) else { continue }
                visited.insert(url.path)

                let total = DiskScanner.sequentialSize(of: url)
                var buildBytes: Int64 = 0
                let buildDir = url.appendingPathComponent("build")
                if fm.fileExists(atPath: buildDir.path) {
                    buildBytes = DiskScanner.sequentialSize(of: buildDir)
                }
                installs.append(LlamaInstall(
                    kind: .source,
                    name: url.lastPathComponent,
                    path: url.path,
                    version: Self.gitDescribe(at: url),
                    totalBytes: total,
                    buildBytes: buildBytes,
                    executables: Self.llamaExecutables(in: url)
                ))
                enumerator.skipDescendants()
            }
        }
        return installs
    }

    private static func llamaExecutables(in checkout: URL) -> [String] {
        let buildBin = checkout.appendingPathComponent("build/bin")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: buildBin, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }
        return entries
            .filter { $0.lastPathComponent.hasPrefix("llama-") }
            .map { $0.path }
            .sorted()
    }

    // MARK: - Model caches

    public func llamaCacheModels() -> [ModelDirInfo] {
        let cacheRoot = homeDirectory.appendingPathComponent(".cache/llama.cpp")
        return modelDirsUnder(cacheRoot, source: .llamaCache)
    }

    public func huggingFaceModels() -> [ModelDirInfo] {
        let hubRoot = homeDirectory.appendingPathComponent(".cache/huggingface/hub")
        return modelDirsUnder(hubRoot, source: .huggingFace)
    }

    /// LM Studio: ~/.lmstudio/models/<publisher>/<model>/…gguf
    public func lmStudioModels() -> [ModelDirInfo] {
        let root = homeDirectory.appendingPathComponent(".lmstudio/models")
        return modelDirsUnder(root, source: .lmStudio)
    }

    /// Jan: ~/Library/Application Support/Jan/models/<model>/…gguf
    public func janModels() -> [ModelDirInfo] {
        let root = homeDirectory.appendingPathComponent("Library/Application Support/Jan/models")
        return modelDirsUnder(root, source: .jan)
    }

    /// GPT4All: loose *.gguf files in ~/Library/Application Support/nomic.ai/GPT4All
    public func gpt4AllModels() -> [ModelDirInfo] {
        let root = homeDirectory.appendingPathComponent("Library/Application Support/nomic.ai/GPT4All")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let ggufs = Self.ggufFiles(under: root)
        let size = DiskScanner.sequentialSize(of: root)
        guard size > 0 else { return [] }
        return [ModelDirInfo(
            source: .gpt4all,
            name: root.lastPathComponent,
            path: root.path,
            totalBytes: size,
            ggufFiles: ggufs
        )]
    }

    public func customFolderModels() -> [ModelDirInfo] {
        var result: [ModelDirInfo] = []
        for rawFolder in customFolders {
            let folder = Self.expandingTilde(rawFolder, home: homeDirectory)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            let ggufs = Self.ggufFiles(under: folder)
            let size = ggufs.reduce(Int64(0)) { $0 + $1.size }
            result.append(ModelDirInfo(
                source: .customFolder,
                name: folder.lastPathComponent,
                path: folder.path,
                totalBytes: size,
                ggufFiles: ggufs
            ))
        }
        return result
    }

    /// Sizes every direct child directory of `root` and collects its GGUF files.
    private func modelDirsUnder(_ root: URL, source: ModelSource) -> [ModelDirInfo] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { dir -> ModelDirInfo in
                let ggufs = Self.ggufFiles(under: dir)
                let size = DiskScanner.sequentialSize(of: dir)
                return ModelDirInfo(
                    source: source,
                    name: Self.prettyModelName(dir.lastPathComponent),
                    path: dir.path,
                    totalBytes: size,
                    ggufFiles: ggufs
                )
            }
            .filter { $0.totalBytes > 0 }
            .sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - GGUF helpers

    public static func ggufFiles(under root: URL) -> [GGUFFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
            options: []
        ) else { return [] }

        var files: [GGUFFile] = []
        for case let url as URL in enumerator {
            let path = url.path
            if IgnoreRules.shared.excludes(path: path) { continue }
            guard url.pathExtension.lowercased() == "gguf" else { continue }
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            files.append(GGUFFile(
                path: path,
                size: size,
                fingerprint: Self.fingerprint(of: url, size: size),
                meta: GGUFMeta.parse(at: url)
            ))
        }
        return files.sorted { $0.size > $1.size }
    }

    /// Dedupes GGUF files by fingerprint; groups with more than one entry are duplicates.
    public static func duplicateGroups(of files: [GGUFFile]) -> [[GGUFFile]] {
        var byFingerprint: [String: [GGUFFile]] = [:]
        for file in files { byFingerprint[file.fingerprint, default: []].append(file) }
        return byFingerprint.values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.size ?? 0) > ($1.first?.size ?? 0) }
    }

    /// Cheap identity check: size plus FNV-1a over the first and last 256 KB.
    public static func fingerprint(of url: URL, size: Int64) -> String {
        let chunk = 256 * 1024
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        func mix(_ data: Data) {
            for byte in data {
                hash ^= UInt64(byte)
                hash = hash &* prime
            }
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "size:\(size)"
        }
        defer { try? handle.close() }
        mix((try? handle.read(upToCount: chunk)) ?? Data())
        if size > Int64(chunk) {
            let offset = max(0, size - Int64(chunk))
            try? handle.seek(toOffset: UInt64(offset))
            mix((try? handle.read(upToCount: chunk)) ?? Data())
        }
        return "size:\(size) hash:\(String(hash, radix: 16))"
    }

    // MARK: - Helpers

    public static func expandingTilde(_ path: String, home: URL) -> URL {
        if path == "~" || path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    /// "models--Qwen--Qwen2.5-7B-GGUF" → "Qwen/Qwen2.5-7B-GGUF"
    public static func prettyModelName(_ raw: String) -> String {
        if raw.hasPrefix("models--") {
            return raw.dropFirst("models--".count)
                .replacingOccurrences(of: "--", with: "/")
        }
        return raw
    }

    public static func gitDescribe(at checkout: URL) -> String? {
        // Guard against paths that would parse as git options (hardening).
        let path = checkout.path.hasPrefix("-") ? "./" + checkout.path : checkout.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "describe", "--tags", "--always", "--dirty"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (out?.isEmpty == false) ? out : nil
        } catch {
            return nil
        }
    }
}
