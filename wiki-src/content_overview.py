ARTICLES = [
    dict(
        slug="overview-architecture", title="MacSpaces — Architecture Overview", category="overview",
        path="(system)", lines=0, lang="SwiftUI / Swift 5.9", status="SPEC", pkg="MacSpaces",
        phase="v1.0", spec_refs=["README.md"], tested_by="macspaces-tests", related=["overview-user-guide", "models-swift", "diskscanner-swift", "appmodel-swift"],
        lead=[
            "MacSpaces is a native macOS utility that monitors disk usage and reclaims space, with purpose-built audits for local AI tooling: Ollama model stores and llama.cpp installs/models. It ships as a single ad-hoc-signed .app bundle built entirely with SwiftPM — no Xcode project, no external dependencies, no sandbox.",
            "The codebase is split into two SwiftPM targets with a strict dependency direction. MacSpacesCore holds everything that thinks: value types, three scanners, and three services — no SwiftUI, linkable by both the app and the macro-free test runner. The MacSpaces app target holds everything that draws: the @main scene, a menu bar extra, and seven SwiftUI views. Views observe AppModel (an ObservableObject injected via .environmentObject) and never touch the filesystem directly; every mutation flows through AppModel, which delegates to Core services and re-runs the relevant audit afterward.",
        ],
        sections=[
            ("Data flow", [
                "Views call AppModel methods (scanDisk, runOllamaAudit, runLlamaAudit, delete*). AppModel runs blocking filesystem work on Task.detached(priority: .userInitiated) so the MainActor never stalls, then hops back to publish results. Long scans stream progress into a ScanStats actor that a dedicated sampling task reads every 250 ms and republishes as a ScanProgress value, giving live item/byte counters without locks on the UI path.",
                "Deletion is centralized in TrashService: Trash by default, permanent deletion behind a DeletionMode stored in UserDefaults. After any delete, AppModel refreshes the affected audit (RefreshTarget OptionSet: .ollama, .llama, .disk) so counts and reclaimable-size numbers never go stale on screen.",
            ]),
            ("Why a two-target split", [
                "The original single-target layout broke on this machine's toolchain: the Command Line Tools 27.0 SDK ships a macro-based SwiftUI but omits the SwiftUIMacros plugin, and macOS 26.5 SDK's SwiftUICore.tbd refuses to link into non-app executables, which made a test target that linked the app module impossible. Splitting Core out gave the test runner a SwiftUI-free module to link against. The toolchain quirks are documented in build-app.sh, which auto-detects the missing plugin and falls back to the 26.5 SDK.",
                "The split also forced a real public API: Models.swift and the services expose public declarations, scanners stay internal (audits run inside Core; views only see results). The test runner uses @testable import MacSpacesCore, which works in debug builds because SwiftPM passes -enable-testing there — release builds must build only the app product, which scripts/build-app.sh enforces with --product MacSpaces.",
            ]),
            ("Safety model", [
                "Every destructive action funnels through TrashService with an explicit DeletionMode. Trash is the default everywhere; permanent deletion is opt-in in Settings and every dialog spells out the byte count and consequence. Ollama orphan cleanup is hard-wired to .trash regardless of the setting. Deleting a single Ollama model uses OllamaAuditor.blobsUniqueTo to remove only the manifest plus blobs referenced by no other manifest — shared layers are never destroyed. The app reads ~/.ollama/ollama.pid and probes it with kill(pid, 0), showing a Running badge so users know blob deletions take effect after the server restarts.",
            ]),
            ("Scan discipline", [
                "The whole-disk scanner skips /System/Volumes (APFS firmlinks would double-count user data), /dev, /private/var/vm, /Volumes and kernel noise anywhere, and skips symlink entries entirely (never counts a target twice). Sizes prefer totalFileAllocatedSize (what Finder shows) over logical file size. Permission-denied directories become nodes with accessDenied=true — rendered as a lock icon — instead of failing the scan.",
            ]),
        ],
        key_items=[
            ("MacSpacesCore (library target)", "Models, DiskScanner, OllamaAuditor, LlamaAuditor, AppModel, TrashService, VolumeMonitor — no SwiftUI"),
            ("MacSpaces (executable target)", "@main scene, MenuBarExtra, seven views under Sources/MacSpaces/Views"),
            ("macspaces-tests (executable target)", "Macro-free test harness; 41 assertions; links Core only"),
            ("scripts/build-app.sh", "swift build → .app bundle with Info.plist, generated icon, ad-hoc signature"),
        ],
    ),
    dict(
        slug="overview-user-guide", title="User Guide — Using MacSpaces Day to Day", category="overview",
        path="(guide)", lines=0, lang="guide", status="SPEC", pkg="MacSpaces",
        phase="v1.0", spec_refs=["USER_GUIDE.md"], tested_by="", related=["overview-architecture", "ollamaauditor-swift", "llamaauditor-swift", "disktree-swift"],
        lead=[
            "This guide walks through every screen of MacSpaces, explains what the audits actually measure, and covers the safety model for deletions. A standalone copy lives at USER_GUIDE.md in the repository root.",
        ],
        sections=[
            ("Build, install, launch", [
                "From the repository root run ./scripts/build-app.sh, which produces build/MacSpaces.app. Add --install to copy it into /Applications. Launch with open build/MacSpaces.app or Finder. Requirements: macOS 13 (Ventura) or newer, Apple Silicon (build universal binaries with swift build -c release --arch arm64 --arch x86_64 for Intel machines).",
                "First launch may show a Gatekeeper prompt because the app is ad-hoc signed. On machines other than the build machine, clear the quarantine flag once with xattr -cr /Applications/MacSpaces.app, or use System Settings → Privacy & Security → Open Anyway.",
            ]),
            ("Dashboard", [
                "The Dashboard opens on the startup volume's usage ring: percent used, used/free/total capacity, refreshed every 30 seconds. Below it sit two audit summary cards — Ollama and llama.cpp — each showing reclaimable space once its audit has run, with a button to run the audit and jump to its tab. After your first disk scan, a chart of the eight largest folders appears with a one-click jump into the Disk Usage drill-down.",
            ]),
            ("Ollama tab — orphaned blobs explained", [
                "Ollama stores every model as content-addressed blobs (~/.ollama/models/blobs/sha256-<hex>) and describes each downloadable model as a manifest (~/.ollama/models/manifests/...) that lists the digests it needs. A blob becomes orphaned when no manifest references it — typically after an interrupted pull, a failed update, or a model deleted while the server held it in a half-written state. Orphans are pure waste; they are safe to move to the Trash.",
                "The Models table lists every manifest with its total size (sum of referenced blobs), unique size (blobs no other manifest uses), and a shared-layers badge. Deleting a model removes its manifest plus only its unique blobs — models sharing a base layer keep that layer on disk. The ~/.ollama Footprint section sizes every top-level directory (logs, backup, cache, keys) so you can see non-model waste too. If the Ollama server is running, the header shows a green Running badge — restart the server after cleanup so it picks up the changes.",
            ]),
            ("llama.cpp tab", [
                "Installations covers two detection paths: Homebrew packages (llama-* binaries in /opt/homebrew or /usr/local, resolved through symlinks to the Cellar, with version from the directory name) and source checkouts (directories containing llama.cpp within your configured scan roots, including build/ artifact size and a git describe version when available).",
                "Models by Location groups GGUF models by source: the llama.cpp download cache (~/.cache/llama.cpp, populated by llama-server -hf), the HuggingFace hub cache (~/.cache/huggingface/hub, with models--org--name rendered as org/name), and your custom folders (default: ~/.ollama/models/ggufs). Duplicate GGUFs are detected by a content fingerprint — file size plus a hash of the first and last 256 KB — and the Duplicates section offers to trash all but one copy of each group.",
            ]),
            ("Disk Usage tab", [
                "Scan your home folder (fast) or the entire disk (slower; can take minutes). While scanning you get a live item count and byte counter plus the current path; Cancel stops it cleanly. The folder tree is sorted by size — click any folder to drill down, right-click for Reveal in Finder or Move to Trash. The Largest Files view lists the 150 biggest files with proportional bars. Deleting a node updates the in-memory tree immediately (ancestor totals shrink) without a full rescan.",
            ]),
            ("Settings and safety", [
                "Settings (menu bar → Settings…, or Cmd-,) controls the default delete behavior: Move to Trash (recommended — everything lands in the Trash and is recoverable) or Delete Permanently (destructive; every dialog still asks). You can add or remove custom GGUF folders and edit the source scan roots used for llama.cpp detection.",
                "Every delete action opens a confirmation dialog showing the item name and byte total. Ollama orphan cleanup is always Trash-only regardless of this setting.",
            ]),
            ("Troubleshooting", [
                "Sizes look incomplete / lock icons: the scan hit permission-denied directories. Grant Full Disk Access (System Settings → Privacy & Security → Full Disk Access) to MacSpaces, or to Terminal when running via swift run, then rescan.",
                "My Ollama models live elsewhere: the auditor reads ~/.ollama/models only. If you launch Ollama with a custom OLLAMA_MODELS path, the app cannot see your shell's environment; keep the default location or symlink it.",
                "App won't open on another Mac ('damaged'): the quarantine flag plus ad-hoc signature. Run xattr -cr on the .app. For distribution without this friction, sign with a Developer ID certificate and notarize.",
            ]),
        ],
        key_items=[
            ("./scripts/build-app.sh [--install]", "Build the .app; optionally copy to /Applications"),
            ("xattr -cr /Applications/MacSpaces.app", "One-time fix for Gatekeeper 'damaged' warnings on other machines"),
            ("Cmd-, / menu bar → Settings…", "Delete mode, custom GGUF folders, source scan roots"),
        ],
    ),
]
