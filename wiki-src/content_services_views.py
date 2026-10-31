ARTICLES = [
    dict(
        slug="appmodel-swift", title="Sources/MacSpacesCore/Services/AppModel.swift", category="core",
        path="Sources/MacSpacesCore/Services/AppModel.swift", lines=335, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="", related=["diskscanner-swift", "ollamaauditor-swift", "trashservice-swift", "scheduledaudit-swift"],
        lead=[
            "The single source of observable truth: volumes, disk tree, four audit results (Ollama, llama.cpp, caches, snapshots), scan progress, watch alerts, and deletion feedback. Views inject it via .environmentObject; every mutation is a method here.",
        ],
        sections=[
            ("Audits and scanning", [
                "runOllamaAudit / runLlamaAudit / runCachesAudit / runSnapshotAudit all run blocking work on Task.detached(priority: .userInitiated) and publish on the MainActor. scanDisk drives DiskScanner plus a 250 ms progress sampler; cancelScan cancels cooperatively.",
                "Settings are read at audit time from UserDefaults — customGGUFFolders and sourceScanRoots now distinguish 'explicitly set' (UserDefaults.object(forKey:) != nil) from unset, so an emptied GGUF list stays empty instead of silently reverting to the default folder.",
            ]),
            ("Deletion with re-verification", [
                "cleanOrphanedBlobs(urls:) is the TOCTOU-safe cleanup: a detached task re-runs OllamaAuditor().audit(), intersects the requested URLs (or the full orphan list) with still-orphaned paths, trashes only those, publishes the fresh audit, and reports 'N moved, M skipped — now referenced by a model'. Hard-wired to Trash regardless of the delete-mode setting.",
                "deleteOllamaModel forces Trash and re-verifies: a detached task re-runs the audit, locates the model fresh, and trashes manifest + blobsUniqueTo from the fresh set — the stale-audit TOCTOU fixed. exportReport refuses symlinked save targets via the same isSafeWriteTarget guard. cleanCacheItems trashes selected CacheItems and re-runs the caches audit. deleteDiskNode splices the node out of the in-memory tree via DiskNode.removing so ancestor totals shrink instantly. exportReport runs ScheduledAudit.run() synchronously and writes through NSSavePanel.",
            ]),
        ],
        key_items=[
            ("public func cleanOrphanedBlobs(urls: [URL]?)", "Re-verified, Trash-only orphan cleanup"),
            ("public func runCachesAudit() / runSnapshotAudit() / thinSnapshots()", "v1.1 audit surfaces"),
            ("public func exportReport() -> URL?", "Save-panel JSON report export"),
        ],
    ),
    dict(
        slug="ignorerules-swift", title="Sources/MacSpacesCore/Services/IgnoreRules.swift", category="core",
        path="Sources/MacSpacesCore/Services/IgnoreRules.swift", lines=110, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="macspaces-tests", related=["diskscanner-swift", "settingsview-swift"],
        lead=[
            "Glob ignore patterns honored by the disk scanner, sequentialSize, and GGUF collection. Patterns live in UserDefaults under ignorePatterns, one per line; # lines are comments.",
        ],
        sections=[
            ("Semantics", [
                "Bare names ('build') match a directory/file of that name anywhere. Trailing-slash rules ('node_modules/') exclude the directory and everything below it, anywhere in the tree. Globs containing '/' are anchored to the full path; otherwise they may match at any depth ('*.tmp' matches temp files everywhere). '*' stays within one segment, '**' crosses slashes, '?' is one non-slash character, and regex metacharacters are escaped by compile(). Star runs collapse to a single quantifier and patterns are capped (256 chars, 500 rules) so pathological input cannot backtrack-blow up the per-file excludes() call — a timing regression test proves a 300-token pattern stays fast.",
                "excludes(path:) checks directory prefixes first, then compiled regexes; setPatterns recompiles under a lock. Tests cover bare names, descendant matching, segment-crossing semantics, metacharacter escaping, and the empty case. A testing initializer (forTesting:) builds instances without touching UserDefaults so tests never pollute the app singleton.",
            ]),
        ],
        key_items=[
            ("public func excludes(path: String) -> Bool", "The single decision point scanners call"),
            ("static func compile(_ glob: String)", "Glob → anchored-or-anywhere regex"),
        ],
    ),
    dict(
        slug="watchservice-swift", title="Sources/MacSpacesCore/Services/WatchService.swift", category="core",
        path="Sources/MacSpacesCore/Services/WatchService.swift", lines=73, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="", related=["appmodel-swift", "dashboardview-swift", "settingsview-swift"],
        lead=[
            "Polls user-configured folders every 5 minutes and raises WatchAlert values when a folder grows past its threshold. Polling rather than FSEvents for v1 — correct, dependency-free, cheap for the handful of watched folders.",
        ],
        sections=[
            ("Details", [
                "Folders and the GB threshold live in UserDefaults (watchFolders newline-joined, watchThresholdGB). check() guards re-entrancy with inFlight, sizes each folder on a detached utility task via sequentialSize, and replaces the alert list with current violations (dedupe by folder). AppModel starts one check at init and DashboardView renders alerts; the timer is invalidated in deinit.",
            ]),
        ],
        key_items=[
            ("public func check() async", "Re-size all watched folders, refresh alerts"),
            ("public static func setFolders(_:) / setThresholdGB(_:)", "Settings persistence"),
        ],
    ),
    dict(
        slug="scheduledaudit-swift", title="Sources/MacSpacesCore/Services/ScheduledAudit.swift", category="core",
        path="Sources/MacSpacesCore/Services/ScheduledAudit.swift", lines=184, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["appmodel-swift", "macspacesapp-swift"],
        lead=[
            "The headless audit pipeline and CLI companion: MacSpaces --audit-json prints a JSON report to stdout; --scheduled-audit writes it to ~/Library/Application Support/MacSpaces/last-audit.json and posts a digest notification via osascript (works from launchd without notification entitlements).",
        ],
        sections=[
            ("Report and launchd", [
                "run() executes every audit synchronously (CLI context) — Ollama, llama.cpp, caches, plus volumes read without a MainActor timer — into the Codable AuditReport. MacSpacesApp.init dispatches on CommandLine.arguments and exits before any UI is created.",
                "setLaunchAgent(enabled:) writes ~/Library/LaunchAgents/com.macspaces.audit.plist (ProgramArguments: the app binary + --scheduled-audit, StartCalendarInterval Friday 10:00) and loads/unloads it via /bin/launchctl. isLaunchAgentInstalled backs the Settings toggle. Note: run() inside ScheduledAudit shadows TMSnapshots.run — the launchctl calls must qualify the latter (a name-collision compile error caught during the build).",
            ]),
        ],
        key_items=[
            ("static func handleLaunchArguments() -> Bool", "CLI dispatch; returns true when the caller should exit"),
            ("static func run() -> AuditReport", "Synchronous full audit → Codable report"),
            ("static func setLaunchAgent(enabled:)", "Weekly digest via com.macspaces.audit"),
            ("static func isSafeWriteTarget(_:)", "Refuses symlinked targets / missing parents for fixed-path writes"),
        ],
    ),
    dict(
        slug="tmsnapshots-swift", title="Sources/MacSpacesCore/Services/TMSnapshots.swift", category="core",
        path="Sources/MacSpacesCore/Services/TMSnapshots.swift", lines=68, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="", related=["cachesview-swift"],
        lead=[
            "Lists and thins APFS local Time Machine snapshots through /usr/bin/tmutil. Snapshot dates are parsed from com.apple.TimeMachine.<stamp>.local names; sizes are not reported (tmutil does not expose them) — snapshot storage is purgeable space already reflected in free-space numbers.",
        ],
        sections=[
            ("Details", [
                "list(mountPoint:) parses 'Snapshots for …' output, warning on unrecognized lines. thin(targetBytes:mountPoint:) runs 'tmutil thinlocalsnapshots / <bytes> 4' — asks the system to delete oldest snapshots until up to the target is freed (the app requests 20 GB); requires no special privileges and never touches backup drives. run() verifies the executable exists and returns tmutil's combined output for display.",
            ]),
        ],
        key_items=[
            ("static func list(mountPoint:) -> Listing", "Snapshot names + parsed dates"),
            ("static func thin(targetBytes:mountPoint:)", "Purgeable-space reclaim via tmutil"),
        ],
    ),
    dict(
        slug="trashservice-swift", title="Sources/MacSpacesCore/Services/TrashService.swift", category="core",
        path="Sources/MacSpacesCore/Services/TrashService.swift", lines=38, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=["README.md"], tested_by="", related=["appmodel-swift", "models-swift"],
        lead=[
            "Every destructive operation funnels through this file — one choke point for the safety model: Trash by default, permanent deletion behind an explicit mode, Finder reveal for verification.",
        ],
        sections=[
            ("Design", [
                "deleteMode is UserDefaults-backed and @MainActor so Settings and AppModel always agree. deleteOne uses FileManager.trashItem (trashing a symlink trashes the link, never its target) or removeItem, returning per-URL DeleteOutcome so batches report 'Moved 5, failed 1: …'. deleteOne first consults refusalReason(for:), which refuses '/' and the home directory itself — a guard against pathological configured paths. revealInFinder uses NSWorkspace.activateFileViewerSelecting. The app is non-sandboxed, which full-disk trashItem requires.",
            ]),
        ],
        key_items=[
            ("public static var deleteMode: DeletionMode", "UserDefaults-backed default"),
            ("public static func delete(_:mode:) -> [DeleteOutcome]", "Batch delete with per-file outcomes"),
        ],
    ),
    dict(
        slug="volumemonitor-swift", title="Sources/MacSpacesCore/Services/VolumeMonitor.swift", category="core",
        path="Sources/MacSpacesCore/Services/VolumeMonitor.swift", lines=49, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.1", spec_refs=[], tested_by="", related=["macspacesapp-swift", "dashboardview-swift"],
        lead=[
            "Polls mounted volumes every 30 s for the Dashboard ring and menu bar label. Uses volumeAvailableCapacityForImportantUsage — the same number Finder reports, accounting for purgeable space (including local TM snapshots).",
        ],
        sections=[
            ("Details", [
                "refresh() reads skipHiddenVolumes, drops zero-capacity entries, pins the root volume first, and publishes VolumeInfo values. A plain Timer fires on the main run loop, marshalled into the MainActor. VolumeInfo.usedFraction guards division by zero.",
            ]),
        ],
        key_items=[
            ("public init(pollInterval: TimeInterval = 30)", "Starts the refresh timer immediately"),
        ],
    ),
    dict(
        slug="macspacesapp-swift", title="Sources/MacSpaces/MacSpacesApp.swift", category="core",
        path="Sources/MacSpaces/MacSpacesApp.swift", lines=124, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=[], tested_by="", related=["contentview-swift", "volumemonitor-swift", "scheduledaudit-swift"],
        lead=[
            "The @main scene graph: WindowGroup (ContentView, 980×640 min), Settings (SettingsView), and a MenuBarExtra — all sharing one AppModel. App.init dispatches CLI flags (ScheduledAudit.handleLaunchArguments) and exits before any UI when running headless.",
        ],
        sections=[
            ("Menu bar quick clean", [
                "The MenuBarExtra label observes VolumeMonitor directly (nested ObservableObjects don't propagate through AppModel) and renders '% free · bytes'. Its menu lists volumes, a Quick clean section — trash all orphaned Ollama blobs / trash duplicate GGUFs with live counts and byte totals, disabled when audits show nothing, plus a Run audits fallback — and the Settings opener.",
                "openSettings() walks the responder chain with runtime selectors (showSettingsWindow: / showSettings: / showPreferencesWindow:) because @Environment(\\.openSettings) is macOS 14+ while the deployment target is 13.",
            ]),
        ],
        key_items=[
            ("MacSpacesApp.init", "CLI dispatch before scene creation"),
            ("MenuBarContent Quick clean", "One-click orphan/duplicate cleanup from the menu bar"),
        ],
    ),
    dict(
        slug="components-swift", title="Sources/MacSpaces/Views/Components.swift", category="core",
        path="Sources/MacSpaces/Views/Components.swift", lines=141, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=[], tested_by="", related=["dashboardview-swift", "ollamaview-swift", "cachesview-swift"],
        lead=[
            "The four reusable visual primitives every tab builds from: UsageRing (gradient gauge that shifts to orange/red past 90%), StatCard (titled metric card), SizeBar (clamped proportional capsule), StatusBadge (tint pill), plus SectionHeader with a trailing button slot.",
        ],
        sections=[
            ("Details", [
                "StatCard's parameter order (detail → systemImage → color) caused two compile-time argument-order errors during the first build — the views now call it consistently. UsageRing carries an accessibility label with the percent used.",
            ]),
        ],
        key_items=[
            ("UsageRing(usedFraction:centerTitle:centerSubtitle:ringSize:)", "Gauge with accessibility label"),
            ("StatCard(title:value:detail:systemImage:color:)", "Metric card used across all headers"),
        ],
    ),
    dict(
        slug="contentview-swift", title="Sources/MacSpaces/Views/ContentView.swift", category="core",
        path="Sources/MacSpaces/Views/ContentView.swift", lines=89, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=[], tested_by="", related=["dashboardview-swift", "cachesview-swift", "appmodel-swift"],
        lead=[
            "The NavigationSplitView shell: five sidebar destinations (Dashboard, Disk Usage, Ollama, llama.cpp, Caches & Snapshots) with live badges, and a detail switch on selection.",
        ],
        sections=[
            ("Details", [
                "Rows use Label + .tag(item) against List(selection:) — an earlier NavigationLink(value:) draft had no matching destination and never switched views. Badges are Optional Int mapped to Text so zero renders nothing (the Int overload renders a literal '0'); Ollama shows its orphan count, llama.cpp its duplicate-group count. A safeAreaInset strip surfaces model.lastDeletionSummary under every tab.",
            ]),
        ],
        key_items=[
            ("enum SidebarItem", "Five destinations incl. the v1.1 caches tab"),
            ("badgeCount(for:) -> Int?", "nil-when-zero badges"),
        ],
    ),
    dict(
        slug="dashboardview-swift", title="Sources/MacSpaces/Views/DashboardView.swift", category="core",
        path="Sources/MacSpaces/Views/DashboardView.swift", lines=283, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=["README.md"], tested_by="", related=["volumemonitor-swift", "watchservice-swift", "components-swift"],
        lead=[
            "The landing screen: storage ring, three audit summary cards with one-click audit runs that deep-link into their tabs, watched-folder alerts, and the largest-folders chart after the first scan.",
        ],
        sections=[
            ("Details", [
                "auditCard is generic over its content and keyed by title — 'Ollama' and 'llama.cpp' switch the sidebar selection after running their audit, 'Caches' runs the v1.1 caches audit and jumps to the new tab. Each card shows its headline number (orphaned bytes, duplicate reclaimable bytes, total cache bytes) or 'Not audited', with an inline spinner while the detached audit runs.",
                "watchAlertsSection renders WatchService alerts — folder (tilde-ified), threshold, check time, current size — only when violations exist. The chart is Swift Charts BarMarks over the top 8 first-level children of the last scan root with byte annotations.",
            ]),
        ],
        key_items=[
            ("auditCard(title:systemImage:tint:content:)", "Generic summary card driving audits from the Dashboard"),
            ("watchAlertsSection", "Folder-watcher violations (feature 5)"),
        ],
    ),
    dict(
        slug="disktree-swift", title="Sources/MacSpaces/Views/DiskTreeView.swift", category="core",
        path="Sources/MacSpaces/Views/DiskTreeView.swift", lines=311, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=["README.md"], tested_by="macspaces-tests", related=["diskscanner-swift", "appmodel-swift"],
        lead=[
            "The whole-disk explorer: three view modes (Space Map, Directory tree, Largest Files), NavigationStack drill-down, live scan progress with cancel, and per-node delete/reveal. The mode picker sits in principal toolbar placement with short labels — centered and untruncated.",
        ],
        sections=[
            ("Details", [
                "Three states: scanning (spinner, current-path ticker, live item/byte counters), empty state with a prominent home-scan button, and results. The Rescan menu offers Home or Entire Disk — the full scan is confirmed first (duration + permission warning + note that ignore rules apply). Directories are NavigationLinks pushing DiskNode values; rows carry Reveal/Trash context menus.",
                "onDeleteConfirmation(target:model:) is a shared ViewModifier honoring the app delete mode — under permanent mode it offers a 'Move to Trash Instead' escape hatch and spells out irreversibility. On confirm, AppModel.deleteDiskNode deletes on disk and shrinks ancestor totals in the in-memory tree instantly.",
            ]),
        ],
        key_items=[
            ("enum ScanTarget", ".home vs .fileSystemRoot (confirmed first)"),
            ("onDeleteConfirmation(target:model:)", "Shared delete dialog honoring DeletionMode"),
        ],
    ),
    dict(
        slug="ollamaview-swift", title="Sources/MacSpaces/Views/OllamaView.swift", category="core",
        path="Sources/MacSpaces/Views/OllamaView.swift", lines=381, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=["README.md"], tested_by="", related=["ollamaauditor-swift", "appmodel-swift"],
        lead=[
            "The Ollama screen: header stat cards, the orphan workbench, the model table, Version Groups, and the ~/.ollama footprint. Auto-runs its audit on first appearance.",
        ],
        sections=[
            ("Orphans and models", [
                "Orphan rows are checkbox-selectable with per-blob reveal; the cleanup dialog explains the deletion-time re-verification ('blobs claimed by a new pull in the meantime are skipped'). Clean-up routes through AppModel.cleanOrphanedBlobs with the selected URLs (or nil for all). Model rows show quant badges (via OllamaAuditor.looksLikeQuantTag), shared/missing badges, and unique size — the number that disappears if you delete the model. Delete always goes to Trash with shared layers kept.",
            ]),
            ("Version Groups", [
                "Rendered only when multi-tag groups exist: base name, total group size, variants newest-first (star = newest), quant badges, per-variant size and delete. Deleting a variant reuses the standard model-delete dialog and refreshes the audit.",
            ]),
        ],
        key_items=[
            ("orphanSection(_:)", "Selectable orphans + re-verification-aware cleanup"),
            ("versionGroupsSection(_:)", "Version manager UI (feature 3)"),
        ],
    ),
    dict(
        slug="llamaview-swift", title="Sources/MacSpaces/Views/LlamaView.swift", category="core",
        path="Sources/MacSpaces/Views/LlamaView.swift", lines=379, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=["README.md"], tested_by="", related=["llamaauditor-swift", "ggufmeta-swift", "appmodel-swift"],
        lead=[
            "The llama.cpp screen: install cards, duplicate-GGUF workbench, and models across the six store sources with GGUF header metadata. Auto-runs its audit on first appearance.",
        ],
        sections=[
            ("Details", [
                "Install rows carry kind badges (homebrew/source), the corrected Cellar version or git describe, build/ artifact sizes, and executable counts. Duplicate groups mark the kept copy green and the rest orange; 'Trash Duplicates…' quantifies files and bytes, then deletes via deleteFiles with refresh: [.llama] so the audit and sidebar badge update immediately — and always with mode .trash, matching the dialog text.",
                "Model rows show source badges for all six stores (llama.cpp cache, HuggingFace, LM Studio, Jan, GPT4All, custom) and per-GGUF metadata badges parsed from the header: quantization, architecture, context length.",
            ]),
        ],
        key_items=[
            ("duplicatesSection(_:)", "Fingerprint groups with keep-first marking"),
            ("modelsSection(_:)", "Six-store listing with GGUF meta badges"),
        ],
    ),
    dict(
        slug="cachesview-swift", title="Sources/MacSpaces/Views/CachesView.swift", category="core",
        path="Sources/MacSpaces/Views/CachesView.swift", lines=261, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=[], tested_by="", related=["xcodecachesauditor-swift", "tmsnapshots-swift", "appmodel-swift"],
        lead=[
            "The v1.1 Caches & Snapshots tab: selectable developer-cache cleanup and local Time Machine snapshot management. Both audits auto-run on first appearance.",
        ],
        sections=[
            ("Caches and snapshots", [
                "Cache rows are checkboxes (name with hash stripped, category badge, tilde path, size) with select-all-or-selected cleanup — always Trash, with a dialog noting caches rebuild automatically. Header cards summarize total cache bytes and snapshot count.",
                "Snapshot rows show the tmutil name and parsed date; 'Thin Snapshots…' confirms and calls AppModel.thinSnapshots (up to 20 GB requested), then re-runs the listing and displays tmutil's output text-selectably. Warnings from tmutil (e.g. Time Machine disabled) render inline.",
            ]),
        ],
        key_items=[
            ("cachesSection(_:)", "Selectable cache cleanup (feature 1)"),
            ("snapshotsSection", "TM snapshot list + thin (feature 2)"),
        ],
    ),
    dict(
        slug="settingsview-swift", title="Sources/MacSpaces/Views/SettingsView.swift", category="core",
        path="Sources/MacSpaces/Views/SettingsView.swift", lines=266, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=[], tested_by="", related=["ignorerules-swift", "watchservice-swift", "scheduledaudit-swift"],
        lead=[
            "The Settings scene: delete behavior, GGUF folders, source roots, ignore rules, folder watcher, scheduled audit, and report export — everything persists to UserDefaults and takes effect on the next audit.",
        ],
        sections=[
            ("v1.1 sections", [
                "Ignore Rules is a monospaced TextEditor saved into IgnoreRules.defaultsKey; examples document bare names, trailing-slash dirs, and wildcards. Folder Watcher manages watch folders via a native folder picker (tilde-relative) and a GB threshold TextField. Scheduled Audit toggles the com.macspaces.audit launchd agent (writing one immediate report when enabled) and reflects the installed state on load.",
                "An explicitly emptied custom-GGUF list is saved as an empty string and honored (the load path checks UserDefaults.object(forKey:) != nil before falling back to defaults) — fixing the silent-revert bug. Report Export offers a save-panel JSON dump of the full audit.",
            ]),
        ],
        key_items=[
            ("Ignore Rules editor", "Feature 8: glob patterns honored by scanners"),
            ("Folder Watcher + Scheduled Audit", "Features 5 and 6 configuration"),
        ],
    ),

    dict(
        slug="spacemapview-swift", title="Sources/MacSpaces/Views/SpaceMapView.swift", category="core",
        path="Sources/MacSpaces/Views/SpaceMapView.swift", lines=262, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.1", spec_refs=[], tested_by="", related=["spacemaplayout-swift", "disktree-swift", "appmodel-swift"],
        lead=[
            "The interactive treemap view: renders SpaceMapLayout tiles in a ZStack with the four usability layers the first map lacked — branch coloring, zoom navigation, hover feedback, and a legend.",
        ],
        sections=[
            ("Interaction layers", [
                "Color: hue is a golden-angle function of the depth-0 branch index (stable across zooms), saturation/brightness shift with depth — adjacent branches stay distinguishable and color always answers 'which top-level branch am I in'. Aggregate tiles render gray.",
                "Navigation: clicking a directory tile re-roots the map (zoomPath); a breadcrumb bar shows the chain from the scan root with an escape hatch back to the whole map; the legend strip lists the current view's largest branches with sizes — clicking one zooms. zoomPath resolves defensively: a deleted or rescanned-away subtree falls back to the scan root.",
                "Feedback and action: hovering strokes the tile and fills the info bar (color chip, name, size, percent of view, selectable full path); tiles expose native tooltips; context menus offer zoom, Reveal in Finder, and Move to Trash — Trash-only from the map, routed through AppModel.deleteDiskNode so the in-memory tree and the map update together. Labels follow the tile-size policy: name+size, name-only, or nothing.",
            ]),
        ],
        key_items=[
            ("SpaceMapView(rootNode:)", "Root view: breadcrumbs + map + info bar + legend"),
            ("static func color(topIndex:depth:aggregate:)", "Branch hue + depth shading, shared with the legend"),
        ],
    ),
]