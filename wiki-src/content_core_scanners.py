ARTICLES = [
    dict(
        slug="models-swift", title="Sources/MacSpacesCore/Models/Models.swift", category="core",
        path="Sources/MacSpacesCore/Models/Models.swift", lines=499, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["diskscanner-swift", "ollamaauditor-swift", "llamaauditor-swift", "scheduledaudit-swift"],
        lead=[
            "The shared value-type vocabulary — every scanner output, view rendering, and report field is expressed here. Foundation-only so MacSpacesCore links into consumers that cannot pull in SwiftUI. Everything is public with explicit initializers: release builds do not pass -enable-testing, so internal members would be invisible to the app target.",
        ],
        sections=[
            ("Disk tree and Ollama", [
                "DiskNode is the recursive scan result: path/name/isDirectory, ownBytes vs totalBytes, itemCount, pre-size-sorted children, accessDenied. removing(path:) splices a deleted node out while shrinking ancestors via prefix matching; largestFiles(limit:) powers the Top-150 view. Hashable on path alone — usable as a NavigationStack value.",
                "OllamaModelInfo gained modificationDate (manifest mtime) and baseName (qualifiedName without tag) for the version manager. OllamaModelGroup is a multi-tag base model with variants sorted newest-first; OllamaAudit.versionGroups exposes only groups with 2+ variants.",
            ]),
            ("New v1.1 domains", [
                "GGUFMetaInfo (parsed header: version, tensorCount, architecture, modelName, quantization, contextLength, parameterCountLabel) rides on GGUFFile.meta. ModelSource grew lmStudio/jan/gpt4all alongside llamaCache/huggingFace/customFolder.",
                "CacheItem + CacheCategory + CachesAudit model the Xcode/SwiftPM cache cleaner. SnapshotInfo models a local TM snapshot. WatchAlert is a threshold violation (folder, bytes, threshold, date). AuditReport is the Codable CLI/report schema: volumes, ollama (per-model entries), llama, caches — encoded by JSONEncoder.macSpaces (pretty, sorted, ISO-8601 dates).",
            ]),
            ("Deletion and formatting", [
                "DeletionMode (trash/permanent) is stored raw in UserDefaults; DeleteOutcome carries per-URL success for batch summaries. Format wraps ByteCountFormatter, the sha256: ↔ sha256- digest/filename mapping, and tildify for display paths.",
            ]),
        ],
        key_items=[
            ("DiskNode.removing(path:) / largestFiles(limit:)", "Tree surgery after delete; iterative top-N files"),
            ("OllamaModelGroup / OllamaAudit.versionGroups", "Version-manager grouping (base model → newest-first variants)"),
            ("AuditReport (Codable)", "CLI (--audit-json) and exported report schema"),
        ],
    ),
    dict(
        slug="diskscanner-swift", title="Sources/MacSpacesCore/Scanners/DiskScanner.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/DiskScanner.swift", lines=200, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["ignorerules-swift", "models-swift", "appmodel-swift"],
        lead=[
            "Parallel directory-tree sizer with a bounded task pool, live stats, cancellation — and, as of v1.1, a deadlock fix that the old implementation needed to survive real trees.",
        ],
        sections=[
            ("The deadlock fix", [
                "scanDirectory acquired a semaphore permit at entry and released it in defer — i.e. AFTER awaiting the child TaskGroup. Every child needs a permit, so with concurrency 12, twelve parents blocked waiting on their children hold all twelve permits while their children wait forever. Any real home directory (deep chains, node_modules) triggers it. The fix releases the permit with an explicit synchronous signal() immediately after contentsOfDirectory, before spawning children — the permit now bounds only enumerations, never waits. The regression test (deep 6-level chain and 30-branch fan-out at concurrency 2) hangs under the old code.",
                "The same test caught a counting bug: subdirectories were tallied +1 as a parent entry AND again inside the child's own itemCount — every directory counted twice (19 instead of 13 on the fixture). Directories are now counted only via their own node.",
            ]),
            ("Primitives and skip rules", [
                "AsyncSemaphore is a lock-based counting semaphore (NSLock + CheckedContinuation queue) whose signal() is synchronous — required by the fix. ScanStats is an actor that AppModel samples every 250 ms into ScanProgress. shouldSkip applies two rule sets: noise names (.Spotlight-V100, .Trashes, …) at any depth, and root prefixes (/System/Volumes firmlinks, /dev, /private/var/vm, /Volumes) only when scanning from \"/\" so APFS firmlinks don't double-count. Symlinks are never counted or descended. Sizes prefer totalFileAllocatedSize. IgnoreRules.shared.excludes(path:) is consulted per entry, and sequentialSize honors it too.",
            ]),
        ],
        key_items=[
            ("func scan() async -> DiskNode", "Deadlock-free parallel sizing pass"),
            ("static func sequentialSize(of:)", "One-shot sizer used by every auditor; ignore-rule aware"),
            ("final class AsyncSemaphore", "Synchronous signal() — the enabler of the fix"),
        ],
    ),
    dict(
        slug="ollamaauditor-swift", title="Sources/MacSpacesCore/Scanners/OllamaAuditor.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/OllamaAuditor.swift", lines=290, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["models-swift", "appmodel-swift", "overview-architecture"],
        lead=[
            "The orphan-detection engine parses manifests from both Ollama store layouts, cross-references blob usage, groups multi-tag models, and reports integrity problems and the local store footprint.",
        ],
        sections=[
            ("Dual-layout manifests", [
                "manifestRoots scans both manifests/ and manifests-v2/. parseManifest locates the store root by matching a path component equal to 'manifests' or prefixed 'manifests-'. dedupeMigrationDuplicates keeps one entry per model + tag, preferring manifests-v2 when both layouts contain the same entry. metadata/ (per-GGUF key-value dumps) is never treated as manifests or model blobs.",
            ]),
            ("Shared layers, integrity, version groups", [
                "referenceCounts maps each digest to the number of manifests that use it: zero references means orphaned, and multiple references mean shared. Orphan attribution uses this count directly. missingBlobDigests identifies manifests that refer to blobs absent from disk.",
                "modelGroups(from:) buckets by baseName and sorts variants newest-first by manifest mtime; looksLikeQuantTag regex-matches Q4_K_M/IQ3_XS/Q8_0/F16-style tags. blobsUniqueTo(model:allModels:blobs:) is the per-model delete primitive — shared layers survive. isOllamaRunning probes ~/.ollama/ollama.pid with kill(pid, 0); EPERM (another user's process) correctly reports not-running.",
            ]),
        ],
        key_items=[
            ("func audit() -> OllamaAudit", "Dual-layout manifests → orphans, sharing, groups, footprint"),
            ("static func dedupeMigrationDuplicates(_:)", "manifests/ vs manifests-v2/ resolution (v2 wins)"),
            ("static func modelGroups(from:) / looksLikeQuantTag(_:)", "Version-manager primitives"),
        ],
    ),
    dict(
        slug="llamaauditor-swift", title="Sources/MacSpacesCore/Scanners/LlamaAuditor.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/LlamaAuditor.swift", lines=336, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["ggufmeta-swift", "ignorerules-swift", "models-swift"],
        lead=[
            "Finds llama.cpp installations and GGUF models across six store sources — llama.cpp cache, HuggingFace hub, LM Studio, Jan, GPT4All, custom folders — deduplicating by content fingerprint and attaching parsed GGUF header metadata.",
        ],
        sections=[
            ("Installs", [
                "homebrewInstalls resolves llama-* symlinks in /opt/homebrew/bin and /usr/local/bin through to the Cellar; v1.1 derives the version from the resolved <version> directory (bin → version → package → Cellar check) instead of the package dir name — the old code reported 'llama.cpp' as the version. sourceInstalls walks configured roots 3 levels deep for *llama.cpp* directories, sizes build/ separately, and labels checkouts with git describe (path hardening: '-'-prefixed paths get a './' prefix; fixed arguments, no shell).",
            ]),
            ("Six model sources and GGUF handling", [
                "modelDirsUnder sizes each child of a store root (llama.cpp cache, HF hub, LM Studio ~/.lmstudio/models, Jan under Application Support); GPT4All is a flat folder of loose ggufs; custom folders are user-configured. prettyModelName rewrites models--org--name → org/name.",
                "ggufFiles(under:) fingerprints every *.gguf (FNV-1a over size + first/last 256 KB — 512 KB read regardless of file size) and now parses the GGUF header via GGUFMeta.parse, attaching architecture/quantization/context to each entry. duplicateGroups buckets by fingerprint, keeps only 2+ groups sorted by size.",
            ]),
        ],
        key_items=[
            ("public func audit() -> LlamaAudit", "Installs + six store sources + duplicate groups"),
            ("static func fingerprint(of:size:)", "Dedupe key; cheap on multi-GB files"),
            ("static func gitDescribe(at:)", "Version label with option-injection hardening"),
        ],
    ),
    dict(
        slug="ggufmeta-swift", title="Sources/MacSpacesCore/Scanners/GGUFMeta.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/GGUFMeta.swift", lines=201, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="macspaces-tests", related=["llamaauditor-swift", "models-swift"],
        lead=[
            "Parses GGUF v2/v3 headers to extract model metadata without reading tensor data: after the 'GGUF' magic, u32 version, u64 tensor count, u64 kv count, then KV pairs (u64-len UTF-8 key, u32 value type, value).",
        ],
        sections=[
            ("Reader and extraction", [
                "ByteReader is a sequential little-endian reader over a FileHandle with a total byte budget (8 MB) — malformed or absurd headers bail out cleanly. Strings are u64-length-prefixed; arrays are skipped by computing element byte length (string arrays pop element-by-element; nested arrays stop parsing).",
                "Extracted keys: general.architecture, general.name, general.size_label, general.file_type (mapped through the llama.cpp GGML_FTYPE table — 14 → Q4_K_M etc., unknown → 'ftype N'), and <arch>.context_length in both u32 and u64 encodings (real GGUF files store context as u32). Extraction stops early once everything of interest is found. The fixture test builds a minimal valid GGUF byte-by-byte and asserts all four fields.",
            ]),
        ],
        key_items=[
            ("static func parse(at:) -> GGUFMetaInfo?", "Header-only metadata extraction with 8 MB budget"),
            ("static func quantName(_:)", "GGML_FTYPE → quantization label"),
            ("struct ByteReader", "Budgeted LE reader; skip() for array payloads"),
        ],
    ),
    dict(
        slug="xcodecachesauditor-swift", title="Sources/MacSpacesCore/Scanners/XcodeCachesAuditor.swift", category="core",
        path="Sources/MacSpacesCore/Scanners/XcodeCachesAuditor.swift", lines=77, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="", related=["appmodel-swift", "cachesview-swift"],
        lead=[
            "Sizes reclaimable developer caches: Xcode DerivedData (per project), Archives, iOS Device Support, Simulator caches, and SwiftPM caches (~/Library/Caches/org.swift.swiftpm and ~/Library/org.swift.swiftpm).",
        ],
        sections=[
            ("Details", [
                "DerivedData and Archives are enumerated per child so individual projects can be cleaned; the rest are single items. prettyDerivedName strips the 12-character hash suffix from 'AppName-<hash>' for display. Every location is safe to delete wholesale — Xcode and SwiftPM rebuild on demand — and cleanup always goes to the Trash.",
            ]),
        ],
        key_items=[
            ("public func audit() -> CachesAudit", "Per-project DerivedData entries + monolithic caches, size-sorted"),
        ],
    ),

    dict(
        slug="spacemaplayout-swift", title="Sources/MacSpacesCore/Models/SpaceMapLayout.swift", category="core",
        path="Sources/MacSpacesCore/Models/SpaceMapLayout.swift", lines=228, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="macspaces-tests", related=["spacemapview-swift", "models-swift"],
        lead=[
            "The treemap geometry engine: a pure-CoreGraphics squarified treemap (Bruls, Huizing & van Wijk) over a DiskNode tree. Living in Core — no SwiftUI — keeps the math unit-testable, which is where every layout regression was caught.",
        ],
        sections=[
            ("Readability constraints", [
                "squarify(values:in:) partitions a CGRect into one rect per value with area proportional to value — the worst-ratio row-growing loop replaces the naive alternating split that produced long thin strips. Emitted rects are clamped to the bounds (accumulated FP drift pushed strip edges past the container in the first test run).",
                "tiles(for:in:) subdivides recursively with four readability constraints: children whose tile would fall below minTile (10 pt) per side aggregate into a single gray Other tile; a post-layout pass re-culls kept children that siblings squeezed below minTile on an axis (three iterations — the Other tile absorbs them and reflows); subdivision stops at maxDepth 6 and an 800-tile budget, so huge trees degrade to parent tiles rather than churning thousands of rects.",
                "A lone sub-threshold child cannot produce a visible Other (its area is below minTile² by definition) — aggregates become visible only when several small children sum above the threshold. The culling test fixture encodes exactly that case: five 50 MB children among 70 GB siblings.",
            ]),
        ],
        key_items=[
            ("static func tiles(for:in:) -> [SpaceTile]", "Full layout pass: culling + recursion + budget"),
            ("static func squarify(_:in:) -> [CGRect]", "Area-conserving partition; order-preserving rects"),
            ("static func worst(_:_) -> Double", "Bruls worst-ratio row test"),
        ],
    ),
]
