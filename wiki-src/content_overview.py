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
            ("v1.1 changelog — bugs fixed", [
                "Bounded-pool deadlock: DiskScanner.scanDirectory held its semaphore permit across the child TaskGroup await; 12 blocked parents could hold all 12 permits while children waited forever. The permit is now released immediately after enumeration, before waiting on children. A regression test scans deep (6-level) and wide (30-branch) trees at concurrency 2 — it hangs under the old code.",
                "Item double-counting: the tree scanner added +1 per subdirectory entry AND included the child node's own count — every directory was counted twice. The deep-tree fixture exposed it (19 vs the correct 13).",
                "Orphan-cleanup TOCTOU: between audit and deletion a running Ollama server can reference a previously-orphaned blob in a new pull. cleanOrphanedBlobs now re-runs the audit inside the delete path and trashes only blobs still orphaned; skipped blobs are reported.",
                "Homebrew version reported the package dir name ('llama.cpp') instead of the Cellar version directory; dialogs under permanent-delete mode claimed Trash semantics; sidebar badges rendered '0'; an emptied custom-GGUF list silently reverted to defaults.",
            ]),
            ("Space map usability round", [
                "The first Space Map (alternating HStack/VStack split, 3-color depth cycling, render-everything) produced thin strips, 'More...' label soup, and no way to act on what you saw. Replaced with a proper package: SpaceMapLayout in Core implements the Bruls squarified treemap (area conservation, bounded aspect ratios), area-based culling into an Other aggregate, iterative re-culling of kept children squeezed below minTile on an axis, an 800-tile budget and maxDepth 6, and FP-drift clamping to bounds.",
                "SpaceMapView renders the tiles with color per top-level branch (golden-angle hue, darkening with depth — color answers 'which branch am I in'), a strict label policy (name+size when the tile fits, name when smaller, nothing below), a hover info bar with percent-of-view and full path, click-to-zoom with a breadcrumb bar, a clickable legend, and Reveal/Trash context menus (Trash-only from the map).",
                "The Disk Usage toolbar moved the mode switch to principal placement with short labels (Map / Tree / Files) — it now sits centered in the top bar instead of truncating at the trailing edge.",
                "Testable-by-construction: the layout is pure CoreGraphics in Core; 16 new assertions cover area conservation, the aspect-ratio bound that kills strips, culling, the tile budget, and degenerate inputs. 121 total.",
            ]),
            ("v1.1 security round 2", [
                "Symlink-safe fixed-path writes: ScheduledAudit gained isSafeWriteTarget (refuses symlinked targets and missing parent dirs) and it now guards the audit-report write, the launchd plist write, and the save-panel export — a pre-planted symlink can no longer redirect those writes.",
                "IgnoreRules hardening: runs of '*' collapse to a single quantifier (single '*' = [^/]* within a segment, '**' = .* across segments), patterns are capped at 256 chars and 500 rules — pathological input can no longer backtrack-blow up the per-file excludes() call. The test compiles a 300-token pathological glob and asserts a 200-char path matches in under 0.5 s.",
                "Deletion root guard: TrashService.refusalReason refuses '/' and the home directory itself, so a pathological configured path can never become a catastrophic delete.",
                "Model-delete TOCTOU: deleteOllamaModel now re-runs the audit in the delete path and trashes manifest + unique blobs from the FRESH model set (previously it computed from the stale on-screen audit). Migration dedupe moved before reference counting, so the same model present in manifests/ and manifests-v2/ no longer inflates shared-layer attribution — verified against the live store (26 deduped models, 2 orphans) with an independent implementation.",
            ]),
            ("Installer and open-source packaging", [
                "scripts/build-app.sh grew --universal (arm64+x86_64 fat binary via SwiftPM cross-compilation, verified with lipo) and --dmg (drag-to-Applications UDZO disk image via hdiutil over a staging dir with an /Applications symlink). A bash 3.2 pitfall surfaced in testing: empty array expansion is 'unbound' under set -u, fixed with the ${ARCH_ARGS[@]+…} guard.",
                "scripts/notarize.sh covers distribution: Developer ID signing with --options runtime --timestamp, notarytool submission from a keychain profile, stapler staple, and a final spctl check — printing full credential setup instructions when env vars are absent.",
                "Open-sourced under Apache 2.0 (Copyright 2026 Xtracsys LLC): canonical LICENSE text with the boilerplate appendix, NOTICE (zero third-party content — Apple frameworks only, icon generated at build time), CONTRIBUTING.md (test-gate rules, deletion-surface guardrails, SPDX header convention), .gitignore, and a git repo prepared for GitHub upload.",
            ]),
            ("v1.1 changelog — the ten features", [
                "Xcode/SwiftPM cache cleaner (Caches tab), local Time Machine snapshot listing + thinning via tmutil, Ollama version manager (multi-tag groups, newest-first), GGUF header metadata parsing (architecture, quantization, context length), folder watcher with threshold alerts, weekly launchd audit with digest notification, LM Studio/Jan/GPT4All store support, glob ignore rules honored by scans and GGUF collection, menu-bar quick-clean actions, and JSON report export plus the --audit-json CLI.",
            ]),
            ("Safety model", [
                "Every destructive action funnels through TrashService with an explicit DeletionMode; Trash is the default everywhere and Ollama orphan cleanup is hard-wired to Trash-only with re-verification. Deleting a single Ollama model removes only the manifest plus blobs referenced by no other manifest — shared layers survive. Cache cleanup is Trash-only; snapshot thinning is a purgeable-space system operation that never touches backup drives. The app reads ~/.ollama/ollama.pid and probes it with kill(pid, 0), showing a Running badge so users know to restart the server after cleanup.",
            ]),
            ("Ollama 0.34 store migration", [
                "Ollama 0.34.1 introduces manifests-v2/ (observed on a live 35 GB store as an empty directory skeleton) alongside the classic manifests/ tree. The auditor scans BOTH roots, parses both with the same lenient JSON decoder, and deduplicates model+tag entries in favor of manifests-v2. On the reference machine all 14 live models still live in manifests/, and the 298 unreferenced blobs (3.3 GB — one 1.6 GB leftover plus ~300 small config/tokenizer blobs) are genuine orphans. metadata/ holds per-GGUF kv dumps and is never treated as blobs.",
            ]),
        ],
        key_items=[
            ("MacSpacesCore (library)", "Models, 5 scanners, 7 services — no SwiftUI, test-linkable"),
            ("MacSpaces (executable)", "@main + MenuBarExtra + 8 views; CLI flags dispatch in init"),
            ("macspaces-tests (executable)", "Macro-free harness; 86 assertions; swift run --scratch-path .build/tests macspaces-tests"),
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
