ARTICLES = [
    dict(
        slug="models-swift", title="Sources/MacSpacesCore/Models/Models.swift", category="core",
        path="Sources/MacSpacesCore/Models/Models.swift", lines=347, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="macspaces-tests", related=["diskscanner-swift", "ollamaauditor-swift", "llamaauditor-swift"],
        lead=[
            "The shared value-type vocabulary of the app. Every scanner output, every view rendering, and every test fixture is expressed in these types. The file is deliberately dependency-free (Foundation only) so MacSpacesCore can be linked by consumers that cannot — or may not — pull in SwiftUI.",
            "Everything here is public with explicit public initializers: the app target consumes these types across the module boundary, and release builds do not pass -enable-testing, so internal members would be invisible to the app. Scanners stay internal; only this vocabulary and the services are part of Core's real API surface.",
        ],
        sections=[
            ("DiskNode — the scan tree", [
                "A recursive value type: path, name, isDirectory, ownBytes (files directly inside), totalBytes (inclusive), itemCount, children, accessDenied. Children are stored pre-sorted by totalBytes descending so views never re-sort. Hashable is implemented on path alone — identity is location, which also makes DiskNode usable as a NavigationStack value.",
                "removing(path:) is the surgical delete primitive used after trashing a file: it returns a copy of the tree with the node spliced out, subtracting the removed subtree's bytes and item count from every ancestor via prefix matching (path.hasPrefix(child.path + \"/\")). It clamps to max(ownBytes, …) so totals can never go negative. largestFiles(limit:) does an iterative stack walk collecting files and returns the size-sorted prefix — powers the Top-150 view without recursion-depth concerns.",
            ]),
            ("Ollama value types", [
                "BlobInfo mirrors one file in blobs/: digest (sha256:<hex>), url, size. OllamaModelInfo mirrors one manifest: registry/namespace/name/tag parsed from the path layout manifests/<registry>/<ns>/<name>/<tag>, plus totalSize (sum of referenced blob sizes), uniqueSize (blobs referenced by exactly one manifest — this one), sharedLayerCount, missingBlobDigests (integrity reporting), and layerDigests kept for deletion math. qualifiedName renders registry[/ns/]name:tag.",
                "OllamaAudit is the aggregate returned by OllamaAuditor.audit(): models, allBlobs, orphanedBlobs, sharedBlobDigests, modelsRootSize, footprint (top-level ~/.ollama entries), ollamaRunning, warnings. orphanedBytes and modelsBytes are computed properties.",
            ]),
            ("llama.cpp value types", [
                "LlamaInstall describes either a Homebrew Cellar package or a source checkout (kind, version, totalBytes, buildBytes, executables). ModelDirInfo groups models by ModelSource (.llamaCache, .huggingFace, .customFolder) with the GGUF files found inside. GGUFFile carries a fingerprint string used for duplicate detection. LlamaAudit aggregates installs, modelDirs, duplicateGroups, and duplicateReclaimableBytes (keep-first accounting: every group contributes all but its first member's size).",
            ]),
            ("Formatting and deletion modes", [
                "Format wraps ByteCountFormatter (countStyle .file) and owns the digest ↔ blob-filename mapping: sha256:<hex> ↔ sha256-<hex> via colon/dash replacement. DeletionMode is a String-raw enum (trash, permanent) stored directly in UserDefaults; DeleteOutcome reports per-URL success for batch operations. ScanProgress is the published snapshot of scan state (phase, currentItem, scannedItems, scannedBytes).",
            ]),
        ],
        key_items=[
            ("DiskNode.removing(path:) -> DiskNode", "Splice a node out of the tree, shrinking ancestor totals by prefix match"),
            ("DiskNode.largestFiles(limit:) -> [DiskNode]", "Iterative walk; files sorted by totalBytes descending"),
            ("Format.blobFileName(forDigest:) / .digest(forBlobFileName:)", "sha256: ↔ sha256- round trip for Ollama's content-addressed store"),
            ("LlamaAudit.duplicateReclaimableBytes", "Sum of all-but-first member of each duplicate GGUF group"),
        ],
    ),
    dict(
        slug="diskscanner-swift", title="Sources/MacSpacesCore/Scanners/DiskScanner.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/DiskScanner.swift", lines=194, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="macspaces-tests", related=["models-swift", "appmodel-swift", "ollamaauditor-swift"],
        lead=[
            "Parallel directory-tree sizer. scan() builds a full DiskNode tree from a root URL using a bounded pool of concurrent tasks, with live statistics and cancellation. Also home to sequentialSize(of:) — the one-shot sizer used by both auditors for small footprints.",
        ],
        sections=[
            ("Concurrency architecture", [
                "AsyncSemaphore is a lock-based counting semaphore (NSLock + CheckedContinuation queue). The first implementation was an actor, which failed to compile: scanDirectory needs signal() inside a defer block, and defer cannot await. The class form keeps signal synchronous; the wait path appends its continuation under the lock and suspends. Marked @unchecked Sendable because the lock is the safety argument.",
                "scanDirectory acquires the semaphore (default concurrency 12), enumerates one directory non-recursively with contentsOfDirectory, partitions entries into files (bytes via resourceValues) and subdirectories, then fans the subdirectories out through withTaskGroup — each child re-entering scanDirectory and re-acquiring the semaphore. This bounds total in-flight enumerations regardless of tree width.",
            ]),
            ("What gets skipped, and why", [
                "shouldSkip(path:scanRoot:) applies two rule sets. Names like .Spotlight-V100, .fseventsd, .Trashes, .DocumentRevisions-V100 are skipped at any depth. Absolute prefixes — /System/Volumes, /dev, /private/var/vm, /Volumes, /private/tmp, /cores — apply only when scanning from \"/\": /System/Volumes/Data is the APFS firmlink target containing the very same /Users data, so scanning it from a root scan would double-count everything. The prefix rules deliberately do not apply to home-folder scans, where a folder literally named System/Volumes is legitimately user data (this exact case is unit-tested).",
                "Symlinks are skipped outright — never counted, never descended — which prevents both double counting and cycles. Directory sizes use totalFileAllocatedSize with fileSize as fallback (allocated = what Finder shows and what deletion actually frees).",
            ]),
            ("Progress and cancellation", [
                "ScanStats is an actor accumulating items, bytes, and the current path. AppModel runs a sampling task that reads a snapshot every 250 ms and republishes it as ScanProgress. Cancellation is cooperative: scanDirectory checks Task.isCancelled at entry and before spawning the child group, so Cancel stops the tree walk without leaving partial children in the result.",
            ]),
            ("Access denial", [
                "A contentsOfDirectory throw (permission denied, mostly under ~/Library without Full Disk Access) produces a leaf node with accessDenied=true and zero bytes rather than aborting the scan — the UI renders these as lock-icon nodes so users can see exactly what they are missing.",
            ]),
        ],
        key_items=[
            ("func scan() async -> DiskNode", "Full parallel sizing pass rooted at root"),
            ("static func shouldSkip(path:scanRoot:)", "Two-tier skip rules: noise names anywhere, root prefixes only at \"/\""),
            ("static func sequentialSize(of:) -> Int64", "Single-threaded recursive size; used by auditors for small dirs"),
            ("final class AsyncSemaphore", "Lock-based async counting semaphore; signal() usable from defer"),
        ],
    ),
    dict(
        slug="ollamaauditor-swift", title="Sources/MacSpacesCore/Scanners/OllamaAuditor.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/OllamaAuditor.swift", lines=231, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="macspaces-tests", related=["models-swift", "appmodel-swift", "diskscanner-swift"],
        lead=[
            "The orphan-detection engine. Audits a local Ollama installation by parsing every model manifest, cross-referencing every blob, and reporting orphans, per-model sizes with shared-layer attribution, integrity problems, and the ~/.ollama footprint. Verified against a 31 GB real-world store with an independent implementation: identical results.",
        ],
        sections=[
            ("How Ollama's store works, and how it's parsed", [
                "Ollama stores model weights as content-addressed blobs (blobs/sha256-<hex>) and describes each pullable model as a JSON manifest at manifests/<registry>/<namespace>/<name>/<tag>. Each manifest names a config blob plus layer blobs by digest (sha256:<hex>). OllamaAuditor walks the manifests tree with an enumerator (skipping .DS_Store), decodes each JSON leniently (all fields optional — hf.co manifests differ from registry.ollama.ai ones), and collects config.digest plus every layers[].digest.",
                "blobFiles() lists blobs/sha256-* with allocated sizes and normalizes filenames back to digest form. The audit builds referenceCounts: digest → number of manifests referencing it. A blob with zero references is an orphan — wasted space from interrupted pulls or half-deleted models. A digest with two or more references is a shared layer (e.g. the same embeddings model reused across fine-tunes).",
            ]),
            ("Shared-layer attribution — and the bug it fixed", [
                "After all manifests are parsed, a post-pass recomputes each model's uniqueSize (sum of blobs whose reference count is exactly 1) and sharedLayerCount. The first implementation subtracted audit.sharedBlobDigests — which is only populated after the post-pass runs — so every shared blob was wrongly counted as unique and shared layers showed sizes of 4096/8192 (APFS block size) in the fixtures. The fix filters on referenceCounts directly. This is exactly the class of bug the fixture tests exist to catch: two manifests, one shared layer, expected unique sizes of 12288 and 0.",
            ]),
            ("Integrity and safety", [
                "missingBlobDigests records digests a manifest references but which have no file on disk — the signature of a manually deleted blob store; such models are reported in the UI with a red badge instead of being silently miscounted.",
                "blobsUniqueTo(model:allModels:blobs:) is the delete-a-model primitive: it collects the model's digests, subtracts every digest referenced by any other manifest, and returns the remaining blobs. AppModel.deleteOllamaModel trashes exactly those plus the manifest file — shared layers survive. isOllamaRunning reads ~/.ollama/ollama.pid and probes the pid with kill(pid, 0); garbage pids parse to not-running (tested), and the UI shows a Running badge warning that blob deletions take effect after a server restart.",
                "footprint() sizes every top-level entry under ~/.ollama (logs, backup, cache, keys) with sequentialSize, exposing non-model waste that the blob math can never see. A missing models directory produces a warning entry, not a failure — the audit result always renders.",
            ]),
        ],
        key_items=[
            ("func audit() -> OllamaAudit", "Manifests → referenceCounts → orphans, shared layers, footprint, integrity"),
            ("func referencedDigests(of:) -> [String]", "config.digest + layers[].digest, lenient JSON decode"),
            ("static func blobsUniqueTo(model:allModels:blobs:)", "Blobs safe to delete alongside one manifest"),
            ("static func isOllamaRunning(home:) -> Bool", "kill(pid, 0) probe against ~/.ollama/ollama.pid"),
        ],
    ),
    dict(
        slug="llamaauditor-swift", title="Sources/MacSpacesCore/Scanners/LlamaAuditor.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/LlamaAuditor.swift", lines=297, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="macspaces-tests", related=["models-swift", "appmodel-swift", "diskscanner-swift"],
        lead=[
            "Finds llama.cpp installations (Homebrew and source builds) and every GGUF model store on the machine — llama.cpp's download cache, the HuggingFace hub cache, and user-configured custom folders — then deduplicates loose GGUFs by content fingerprint.",
        ],
        sections=[
            ("Homebrew detection", [
                "homebrewInstalls() scans /opt/homebrew/bin and /usr/local/bin for llama-* entries, resolves each through resolvingSymlinksInPath, and climbs three components up the resolved path (bin → version → llama.cpp → check name) to find the Cellar package directory. The version comes from the Cellar layout: if the parent directory is literally Cellar, the package's child directory name is the version. Sizes come from sequentialSize over the whole package. On the reference machine (no Homebrew llama) this correctly returns an empty list — absence is a result, not an error.",
            ]),
            ("Source-build detection", [
                "sourceInstalls() walks each configured scan root (default: ~/llama.cpp, ~/src, ~/code, ~/Projects, ~/dev, ~/Developer) with a FileManager enumerator capped at depth 3, matching directory names containing llama.cpp. Matched checkouts are sized whole, with build/ sized separately so build artifacts (often the bulk) are visible as reclaimable; gitDescribe shells out to git -C <dir> describe --tags --always --dirty for a version label and fails soft to nil. skipDescendants prevents nested matches from double-reporting.",
            ]),
            ("Model stores and the GGUF fingerprint", [
                "llamaCacheModels() and huggingFaceModels() size every direct child directory of ~/.cache/llama.cpp and ~/.cache/huggingface/hub; prettyModelName rewrites models--org--name into org/name. customFolderModels() scans user-configured folders for *.gguf at any depth — the default folder is ~/.ollama/models/ggufs, which on the reference machine holds a single 10.8 GB GGUF.",
                "fingerprint(of:size:) hashes the first and last 256 KB plus the size with FNV-1a 64 — cheap on multi-GB files (512 KB read regardless of size) while catching both truncated copies and same-size-different-content files. duplicateGroups() buckets by fingerprint and returns only groups of 2+, sorted by size; AppModel's duplicate cleanup trashes every member except the first of each group.",
            ]),
        ],
        key_items=[
            ("public func audit() -> LlamaAudit", "Installs + model dirs + duplicate groups in one pass"),
            ("static func fingerprint(of:size:) -> String", "FNV-1a over head+tail 256 KB and size; dedupe key"),
            ("static func duplicateGroups(of:) -> [[GGUFFile]]", "Groups of 2+ identical GGUFs, largest first"),
            ("static func gitDescribe(at:) -> String?", "git describe version label; nil on any failure"),
        ],
    ),
]
