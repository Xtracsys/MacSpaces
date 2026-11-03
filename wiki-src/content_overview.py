ARTICLES = [
    dict(
        slug="overview-architecture", title="Architecture Overview", category="overview",
        path="(system)", lines=0, lang="SwiftUI / Swift 5.9", status="SPEC", pkg="MacSpaces",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["overview-user-guide", "models-swift", "diskscanner-swift", "appmodel-swift"],
        lead=[
            "MacSpaces is a native macOS utility that monitors disk usage and reclaims space, with purpose-built audits for local AI tooling: Ollama model stores, llama.cpp and other GGUF runtimes (LM Studio, Jan, GPT4All, HuggingFace), Xcode/SwiftPM caches, and APFS local Time Machine snapshots. It ships as a single ad-hoc-signed .app built entirely with SwiftPM, and its binary doubles as a headless CLI auditor (--audit-json / --scheduled-audit).",
            "The codebase splits into two SwiftPM targets. MacSpacesCore holds everything that thinks — value types, five scanners, seven services — with no SwiftUI, so the macro-free test runner can link it. The MacSpaces app target holds everything that draws: the @main scene, a menu bar extra with quick-clean actions, and eight views. Views observe AppModel (injected via .environmentObject) and never touch the filesystem; every mutation flows through AppModel, which delegates to Core services and refreshes the relevant audit afterward.",
        ],
        sections=[
            ("Concurrency and audit integrity", [
                "DiskScanner.scanDirectory releases its bounded-pool permit after directory enumeration and before awaiting child tasks. This prevents parent tasks from occupying every permit while their children wait for one. A deep and wide tree fixture covers the concurrency limit.",
                "Directory totals count each item once: a directory contributes its own node and the descendants reported by its child node. The disk-tree tests cover this accounting rule.",
                "Ollama cleanup re-runs the audit immediately before deletion. Only blobs that remain unreferenced are moved to Trash, so a model pull that starts after the original audit cannot make a shared blob eligible for removal.",
                "Version display uses the installed Homebrew Cellar version. Cleanup dialogs name the selected deletion mode, empty custom-store settings remain empty, and zero-valued badges display consistently.",
            ]),
            ("Space-map design", [
                "SpaceMapLayout uses the Bruls squarified treemap algorithm to preserve area proportions while keeping tile aspect ratios usable. It aggregates small entries, limits depth and tile count, and clamps floating-point drift to the view bounds.",
                "SpaceMapView colors tiles by top-level directory, scales labels to tile size, and provides a hover summary, zoom navigation, breadcrumbs, and a legend. Reveal and Trash actions are available from the map; deletion uses Trash.",
                "The Map / Tree / Files mode switch sits in the main Disk Usage toolbar. The layout is implemented in MacSpacesCore and has focused coverage for area conservation, culling, tile limits, and degenerate inputs.",
            ]),
            ("Safety and data protection", [
                "Scheduled reports, launch-agent files, and user-selected exports reject unsafe targets, including symlinked paths and missing parent folders. Ignore patterns have explicit length and count limits to keep scans predictable.",
                "TrashService refuses deletion of the filesystem root and the user's home directory. Ordinary cleanup uses Trash by default; Ollama orphan cleanup always rechecks references before moving files.",
                "The auditor reads both classic Ollama manifests and the manifests-v2 layout, deduplicates matching models before counting shared layers, and preserves blobs referenced by any manifest.",
            ]),
            ("Build and distribution", [
                "scripts/build-app.sh supports universal arm64 + x86_64 builds and a drag-to-Applications DMG. The script records the SDK fallback and target selection used to keep app builds separate from the test runner.",
                "scripts/notarize.sh documents Developer ID signing, hardened runtime, notarization, ticket stapling, and Gatekeeper verification. It reports the required credential setup when signing credentials are not configured.",
                "The repository includes Apache-2.0 source licensing, a NOTICE file, contributor guidance, and a macOS CI workflow for the app build and test runner.",
            ]),
            ("Additional capabilities", [
                "Xcode/SwiftPM cache cleaner (Caches tab), local Time Machine snapshot listing + thinning via tmutil, Ollama version manager (multi-tag groups, newest-first), GGUF header metadata parsing (architecture, quantization, context length), folder watcher with threshold alerts, weekly launchd audit with digest notification, LM Studio/Jan/GPT4All store support, glob ignore rules honored by scans and GGUF collection, menu-bar quick-clean actions, and JSON report export plus the --audit-json CLI.",
            ]),
            ("Safety model", [
                "Every destructive action funnels through TrashService with an explicit DeletionMode; Trash is the default everywhere and Ollama orphan cleanup is hard-wired to Trash-only with re-verification. Deleting a single Ollama model removes only the manifest plus blobs referenced by no other manifest — shared layers survive. Cache cleanup is Trash-only; snapshot thinning is a purgeable-space system operation that never touches backup drives. The app reads ~/.ollama/ollama.pid and probes it with kill(pid, 0), showing a Running badge so users know to restart the server after cleanup.",
            ]),
            ("Ollama store formats", [
                "The auditor supports the classic manifests/ tree and the manifests-v2/ layout used by newer Ollama versions. Both are parsed with the same decoder, and matching model + tag entries are deduplicated before blob references are counted. Metadata dumps are not treated as model blobs.",
            ]),
        ],
        key_items=[
            ("MacSpacesCore (library)", "Models, 5 scanners, 7 services — no SwiftUI, test-linkable"),
            ("MacSpaces (executable)", "@main + MenuBarExtra + 8 views; CLI flags dispatch in init"),
            ("macspaces-tests (executable)", "Macro-free harness; 121 assertions; swift run --scratch-path .build/tests macspaces-tests"),
            ("scripts/build-app.sh", "Release build → .app with icon; auto-SDK fallback for the CLT macro gap"),
        ],
    ),
    dict(
        slug="overview-user-guide", title="User Guide", category="overview",
        path="(guide)", lines=0, lang="guide", status="SPEC", pkg="MacSpaces",
        phase="v1.1", spec_refs=["USER_GUIDE.md"], tested_by="", related=["overview-architecture", "ollamaauditor-swift", "llamaauditor-swift", "cachesview-swift"],
        lead=[
            "Full walkthrough lives at USER_GUIDE.md in the repository root; this tab summarizes what each screen does and the safety rules that apply everywhere.",
        ],
        sections=[
            ("Screens", [
                "Dashboard: usage ring, three audit summary cards (Ollama / llama.cpp / Caches) with one-click audits, watched-folder alerts, largest-folders chart. Menu bar: live free space plus Quick clean (trash orphans / duplicate GGUFs directly).",
                "Ollama: orphan workbench (selectable, Trash-only, re-verified at deletion), model table with unique-size and shared-layer badges, Version Groups for multi-tag pulls, ~/.ollama footprint. llama.cpp: Homebrew + source installs, duplicate GGUFs by fingerprint, models grouped across six store sources with GGUF header metadata (architecture, quant, context length). Caches & Snapshots: Xcode DerivedData/Archives/DeviceSupport/SwiftPM caches with selection cleanup, plus local TM snapshots with a thin action. Disk Usage: home or whole-disk scans, drill-down tree, top-150 largest files, ignore rules honored.",
            ]),
            ("Safety rules", [
                "Deletions default to Trash (Settings can switch to permanent, with a 'Move to Trash Instead' escape hatch in every dialog). Ollama orphan cleanup is always Trash and always re-verified. Model deletion keeps shared layers. Caches are Trash-only. Snapshot thinning asks macOS to purge up to 20 GB of local snapshots — backups are untouched.",
            ]),
            ("CLI and automation", [
                "MacSpaces --audit-json prints a pretty-printed JSON report (volumes, ollama, llama, caches) to stdout. --scheduled-audit writes it to ~/Library/Application Support/MacSpaces/last-audit.json and posts a digest notification. Settings → Scheduled Audit installs a launchd agent (com.macspaces.audit) running it Fridays at 10:00. Report Export in Settings saves the same JSON anywhere via a save panel.",
            ]),
        ],
        key_items=[
            ("./scripts/build-app.sh [--install]", "Build (and optionally install) the .app"),
            ("MacSpaces --audit-json", "Headless JSON audit report to stdout"),
            ("xattr -cr /Applications/MacSpaces.app", "One-time Gatekeeper fix on other machines"),
        ],
    ),
]
