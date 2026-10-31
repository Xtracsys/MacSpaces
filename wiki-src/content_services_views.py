ARTICLES = [
    dict(
        slug="appmodel-swift", title="Sources/MacSpacesCore/Services/AppModel.swift", category="core",
        path="Sources/MacSpacesCore/Services/AppModel.swift", lines=212, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["diskscanner-swift", "ollamaauditor-swift", "trashservice-swift", "contentview-swift"],
        lead=[
            "The single source of observable truth for the UI: a @MainActor ObservableObject holding the volume list, the disk tree, both audit results, scan progress, and deletion feedback. Views inject it via .environmentObject and never touch the filesystem; every user action is a method call here.",
        ],
        sections=[
            ("Scan orchestration", [
                "scanDisk(root:) guards re-entrancy, resets published state, and starts two tasks: the scan task (DiskScanner.scan() → DiskNode, or scanWasCancelled on cancellation) and a progress sampling task that reads the ScanStats actor every 250 ms into the published ScanProgress. cancelScan() cancels the scan task; the sampling loop exits on its own Task.isCancelled check when the scan task finishes and calls progressTask?.cancel().",
                "Both audits run on Task.detached(priority: .userInitiated) — audits do pure blocking filesystem work and must not occupy the MainActor — then hop back to publish ollamaAudit / llamaAudit. Settings (custom GGUF folders, source scan roots) are read from UserDefaults at audit time, so changes in Settings take effect on the next audit run without restart.",
            ]),
            ("Deletion and refresh", [
                "deleteFiles(at:mode:refresh:) funnels through TrashService with the effective mode (explicit mode, else the UserDefaults-backed deleteMode), reports a one-line summary ('Moved to Trash N items' / failure counts with the first error), then refreshes. RefreshTarget is an OptionSet (.ollama, .llama, .disk) so a llama.cpp cleanup re-runs the llama audit and sidebar badges update in place.",
                "deleteOrphanedBlobs is deliberately hard-wired to .trash — orphans are the one place where even the permanent-delete setting must not apply. deleteOllamaModel computes OllamaAuditor.blobsUniqueTo and trashes manifest + unique blobs only. deleteDiskNode deletes on disk and then splices the node out of the in-memory tree with DiskNode.removing(path:), so ancestor sizes shrink instantly without a rescan (deleting the scan root itself clears the tree).",
            ]),
        ],
        key_items=[
            ("public func scanDisk(root: URL?)", "Async tree scan with 250 ms progress sampling and cancel"),
            ("public func runOllamaAudit() / runLlamaAudit()", "Detached-task audits publishing results on the MainActor"),
            ("public func deleteFiles(at:mode:refresh:)", "Trash/permanent delete + audit refresh via RefreshTarget"),
            ("public func deleteDiskNode(_:mode:)", "Delete plus immediate in-memory tree surgery"),
        ],
    ),
    dict(
        slug="trashservice-swift", title="Sources/MacSpacesCore/Services/TrashService.swift", category="core",
        path="Sources/MacSpacesCore/Services/TrashService.swift", lines=38, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["appmodel-swift", "models-swift"],
        lead=[
            "Every destructive operation in the app goes through this 38-line file — which is the point. One choke point for deletion means one place to audit the safety model: Trash by default, permanent deletion behind an explicit mode, Finder reveal for verification.",
        ],
        sections=[
            ("Design", [
                "deleteMode is backed by UserDefaults key deleteMode and exposed as a static @MainActor property so Settings and AppModel always agree. delete(_ urls:mode:) maps deleteOne over a batch; deleteOne uses FileManager.trashItem for .trash and removeItem for .permanent, returning a DeleteOutcome per URL (success flag + localized error message) so batch reports can say 'Moved 5, failed 1: …' instead of failing silently.",
                "revealInFinder uses NSWorkspace.activateFileViewerSelecting — used by every view's context menus and by the orphan list so users can verify before deleting. The app is non-sandboxed (SwiftPM ad-hoc build), which is what makes full-disk trashItem calls possible without entitlement prompts.",
            ]),
        ],
        key_items=[
            ("public static var deleteMode: DeletionMode", "UserDefaults-backed trash/permanent default"),
            ("public static func delete(_:mode:) -> [DeleteOutcome]", "Batch delete with per-file outcomes"),
            ("public static func revealInFinder(_:)", "NSWorkspace file viewer selection"),
        ],
    ),
    dict(
        slug="volumemonitor-swift", title="Sources/MacSpacesCore/Services/VolumeMonitor.swift", category="core",
        path="Sources/MacSpacesCore/Services/VolumeMonitor.swift", lines=48, lang="Swift", status="CORE", pkg="MacSpacesCore",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["appmodel-swift", "macspacesapp-swift"],
        lead=[
            "Keeps the Dashboard ring and menu bar label honest: polls every mounted volume's capacity every 30 seconds and publishes VolumeInfo values. Small, but it is the 'monitoring' in the app's title.",
        ],
        sections=[
            ("Details", [
                "refresh() reads mountedVolumeURLs(options: .skipHiddenVolumes) and, per volume, volumeTotalCapacity plus volumeAvailableCapacityForImportantUsage — the same 'free space' number Finder reports, which accounts for purgeable space. Volumes with zero/unknown capacity are dropped. Sorting pins the root volume ('/'), i.e. Macintosh HD, first and orders the rest by name; primaryVolume is the first entry and drives the Dashboard ring and the menu bar percentage.",
                "The poll is a plain Timer.scheduledTimer firing on the main run loop, marshalled into the MainActor with Task { @MainActor in }. deinit invalidates the timer. VolumeInfo.usedFraction guards division by zero for volumes reporting zero capacity.",
            ]),
        ],
        key_items=[
            ("public init(pollInterval: TimeInterval = 30)", "Starts the refresh timer immediately"),
            ("public func refresh()", "Manual re-poll (also used on window activation paths)"),
        ],
    ),
    dict(
        slug="macspacesapp-swift", title="Sources/MacSpaces/MacSpacesApp.swift", category="core",
        path="Sources/MacSpaces/MacSpacesApp.swift", lines=88, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=[], tested_by="", related=["contentview-swift", "volumemonitor-swift", "appmodel-swift"],
        lead=[
            "The @main scene graph: a WindowGroup hosting ContentView, a Settings scene hosting SettingsView, and a MenuBarExtra showing live free space — all sharing one @StateObject AppModel.",
        ],
        sections=[
            ("Scenes", [
                "The window enforces a 980×640 minimum via .frame(minWidth:minHeight:), uses .windowToolbarStyle(.unified), and AppDelegate.applicationShouldTerminateAfterLastWindowClosed returns true so quitting the window quits the app — expected utility-app behavior.",
                "The MenuBarExtra label is a small view observing VolumeMonitor directly (not through AppModel — nested ObservableObjects don't propagate), rendering e.g. '34% free · 1.2 TB'. Its menu lists every mounted volume with free/total, an Open button that activates the app and fronts its main window, Settings…, and Quit.",
            ]),
            ("The Settings-open compatibility shim", [
                "The modern @Environment(\\.openSettings) action is macOS 14+, but the deployment target is macOS 13 — referencing it failed to compile against the 26.5 SDK. openSettings() instead walks the responder chain with runtime selectors: showSettingsWindow:, showSettings:, falling back to the legacy showPreferencesWindow:. Works from macOS 13 through 26 with no availability gates.",
            ]),
        ],
        key_items=[
            ("@main MacSpacesApp", "WindowGroup + Settings + MenuBarExtra sharing AppModel"),
            ("VolumeMenuBarLabel", "ObservedObject VolumeMonitor → '% free · bytes' menu bar label"),
            ("MenuBarContent.openSettings()", "Selector-chain Settings opener, macOS 13+ compatible"),
        ],
    ),
    dict(
        slug="components-swift", title="Sources/MacSpaces/Views/Components.swift", category="core",
        path="Sources/MacSpaces/Views/Components.swift", lines=141, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=[], tested_by="", related=["dashboardview-swift", "ollamaview-swift", "llamaview-swift"],
        lead=[
            "The four reusable visual primitives every tab is built from: the usage ring, the stat card, the proportional size bar, and the status badge. Keeping them here is what makes the four audit/detail views nearly repetition-free.",
        ],
        sections=[
            ("Primitives", [
                "UsageRing draws a trimmed circle with an AngularGradient that shifts from blue/teal to orange/red past 90% usage (the same threshold DaisyDisk users expect), rotated −90° to start at 12 o'clock, with centered title/subtitle and an accessibility label. SizeBar is a GeometryReader capsule whose width is a clamped fraction of the container — used in the Largest Files list. StatusBadge is a capsule tint pill (shared-layers, missing-blobs, install kind). StatCard is the titled metric card with icon, value, and detail line used across the Dashboard, Ollama, and llama.cpp headers. SectionHeader pairs a headline/subtitle with a trailing AnyView button slot.",
            ]),
        ],
        key_items=[
            ("UsageRing(usedFraction:centerTitle:centerSubtitle:ringSize:)", "Gradient usage gauge with accessibility label"),
            ("StatCard(title:value:detail:systemImage:color:)", "Metric card; parameter order deliberately detail→systemImage→color"),
            ("SizeBar(fraction:color:)", "Clamped proportional capsule bar"),
        ],
    ),
    dict(
        slug="contentview-swift", title="Sources/MacSpaces/Views/ContentView.swift", category="core",
        path="Sources/MacSpaces/Views/ContentView.swift", lines=79, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=[], tested_by="", related=["dashboardview-swift", "disktree-swift", "ollamaview-swift", "llamaview-swift", "appmodel-swift"],
        lead=[
            "The NavigationSplitView shell: a sidebar of four destinations (Dashboard, Disk Usage, Ollama, llama.cpp) with live badge counts, and a detail switch that renders the selected view.",
        ],
        sections=[
            ("Sidebar pattern", [
                "Rows are Label + .tag(item) against List(selection: $selection) — the plain selection-binding pattern. An earlier draft used NavigationLink(value:), but with the detail rendered by a switch (rather than navigationDestination(for:)) the links had no matching destination; tags make row clicks set selection directly. badgeCount feeds Int badges: orphaned-blob count on the Ollama row, duplicate-group count on the llama.cpp row, zero renders no badge.",
                "A safeAreaInset(edge: .bottom) strip shows model.lastDeletionSummary — the persistent 'Moved to Trash 3 items.' feedback line — so every view gets deletion feedback without duplicating it.",
            ]),
        ],
        key_items=[
            ("enum SidebarItem", "dashboard / disk / ollama / llama with title + systemImage"),
            ("badgeCount(for:)", "Orphan and duplicate-group badges from the current audits"),
        ],
    ),
    dict(
        slug="dashboardview-swift", title="Sources/MacSpaces/Views/DashboardView.swift", category="core",
        path="Sources/MacSpaces/Views/DashboardView.swift", lines=224, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["volumemonitor-swift", "appmodel-swift", "components-swift"],
        lead=[
            "The landing screen: storage summary ring, AI-audit summary cards with one-click audit runs, and the largest-folders chart once a scan exists. Its selection Binding is what lets its buttons deep-link into the Ollama/llama.cpp tabs.",
        ],
        sections=[
            ("Sections", [
                "Storage: UsageRing plus LabeledRow stats (used/free with emphasis/total) for the primary volume, and the 'Analyze disk usage' button that switches to the Disk tab and kicks off a home-folder scan if none exists yet.",
                "Audit summary: two auditCard generically rendered cards — Ollama (purple, pawprint) and llama.cpp (teal, cpu). Each shows either its headline reclaimable number (orphaned bytes / duplicate reclaimable bytes) or 'Not audited', plus a run button with an inline progress spinner while the detached audit task is in flight. The llama card additionally reports total GGUF bytes and location counts when there's nothing to reclaim.",
                "Largest folders: a Swift Charts horizontal BarMark chart of the top 8 first-level children of the last scan root, X axis hidden, byte annotations trailing each bar, with the scan timestamp and a jump link. Chart rows are driven by DiskNode Identifiable conformance.",
            ]),
        ],
        key_items=[
            ("DashboardView(selection:)", "Binding back to ContentView's sidebar for deep links"),
            ("auditCard(title:systemImage:tint:content:)", "Generic summary card; drives audit runs from the Dashboard"),
        ],
    ),
    dict(
        slug="disktree-swift", title="Sources/MacSpaces/Views/DiskTreeView.swift", category="core",
        path="Sources/MacSpaces/Views/DiskTreeView.swift", lines=312, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=["README.md"], tested_by="macspaces-tests", related=["diskscanner-swift", "appmodel-swift", "trashservice-swift"],
        lead=[
            "The whole-disk explorer: NavigationStack drill-down through the scanned tree, a top-150 largest-files mode, live scan progress with cancel, and per-node delete/reveal. It is the only view that owns its own NavigationStack.",
        ],
        sections=[
            ("Scan lifecycle UI", [
                "Three states: scanning (large spinner, root path, current-path ticker truncated to the middle, live item/byte counters from AppModel's 250 ms sampling), empty state with a prominent 'Scan Home Folder' button, and results. The toolbar hosts a segmented Folder Tree / Largest Files picker, a Rescan menu (Home or Entire Disk — the latter behind a confirmation dialog warning about duration and permission-limited folders), and a Cancel button while scanning.",
            ]),
            ("Drill-down and deletion", [
                "The tree renders the current node's summary row (full path, bytes, item count, text-selectable) plus children sorted by size; directories are NavigationLinks pushing DiskNode values via navigationDestination, files are plain rows. A Back row mirrors the stack pop. Rows carry context menus: Reveal in Finder, Move to Trash….",
                "Deletion confirmation is centralized in onDeleteConfirmation(target:model:), a ViewModifier hosting a confirmationDialog that respects the app delete mode — under permanent mode it offers both 'Delete Permanently' and a 'Move to Trash Instead' escape hatch, and the message spells out the byte total and irreversibility. On confirm it calls AppModel.deleteDiskNode, which deletes on disk and shrinks ancestor totals in the in-memory tree instantly.",
                "Largest Files flattens the tree via DiskNode.largestFiles(limit: 150) and renders name, truncated full path, a SizeBar proportional to the largest entry, and monospaced byte counts — same context menus, same confirmation flow.",
            ]),
        ],
        key_items=[
            ("enum ScanTarget", ".home (fast) vs .fileSystemRoot (full scan, confirmed first)"),
            ("onDeleteConfirmation(target:model:)", "Shared delete dialog honoring DeletionMode"),
            ("largestFilesList(root:)", "Top-150 files with proportional bars"),
        ],
    ),
    dict(
        slug="ollamaview-swift", title="Sources/MacSpaces/Views/OllamaView.swift", category="core",
        path="Sources/MacSpaces/Views/OllamaView.swift", lines=325, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["ollamaauditor-swift", "appmodel-swift", "components-swift"],
        lead=[
            "The Ollama audit screen: header stat cards, the orphaned-blob workbench with selection and cleanup, the model table with shared-layer badges, and the ~/.ollama footprint. Auto-runs its audit once on first appearance via .task.",
        ],
        sections=[
            ("Orphan workbench", [
                "Orphans render as checkbox rows (monospaced sha256 filenames) with per-blob reveal. Selection is a Set<BlobInfo.ID>; 'Clean Orphans…' opens a confirmation dialog whose wording adapts — 'All' or the selected count — and the destructive action routes through either model.deleteOrphanedBlobs (all) or deleteFiles with explicit .trash mode (selection). The total reclaimable size is always visible at the bottom of the section. An empty orphan list renders a green checkmark line instead of an empty table.",
            ]),
            ("Models and footprint", [
                "Each model row shows qualifiedName (text-selectable), shared-layer and missing-blob badges, layer count, total size, and 'unique: N' when it differs from total — the number that actually disappears if you delete this model. Row actions reveal the manifest in Finder or open the delete-model dialog, whose message explains that shared blobs are kept and quantifies what will be trashed (the unique size). The header's Running badge warns when the Ollama server holds the blob store. Footprint lists every top-level ~/.ollama entry with size and reveal, exposing non-model waste like logs and backups.",
            ]),
        ],
        key_items=[
            ("orphanSection(_:)", "Selectable orphan list + adaptive Clean Orphans confirmation"),
            ("modelsSection(_:)", "Manifest table with shared/missing badges and per-model delete"),
            ("footprintSection(_:)", "~/.ollama top-level size breakdown"),
        ],
    ),
    dict(
        slug="llamaview-swift", title="Sources/MacSpaces/Views/LlamaView.swift", category="core",
        path="Sources/MacSpaces/Views/LlamaView.swift", lines=365, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["llamaauditor-swift", "appmodel-swift", "components-swift"],
        lead=[
            "The llama.cpp screen: install cards (Homebrew/source with versions and build-artifact sizes), the duplicate-GGUF workbench with one-click reclamation, and models grouped by their store with per-file reveal. Auto-runs its audit on first appearance.",
        ],
        sections=[
            ("Installs and duplicates", [
                "Installations rows carry a kind badge (homebrew / source), the git-describe or Cellar version, the path, executable count, and total/build sizes. An empty result renders an explicit 'nothing found in Homebrew or scanned roots' row rather than blank space, with the scanned roots configurable in Settings.",
                "Duplicates groups list every member with a green kept badge on the first and orange duplicate badges on the rest, full paths text-selectable. 'Trash Duplicates…' opens a dialog quantifying file count and bytes, then deletes all but the first member of each group through model.deleteFiles(refresh: [.llama]) so the audit — and the sidebar badge — refresh immediately.",
            ]),
            ("Models by location", [
                "Each store row shows the pretty name (org/name for HF caches), a source badge (llama.cpp cache / HuggingFace cache / Custom folder), the path, total bytes, GGUF count, and the first four GGUF files with individual reveal links plus an '…and N more' line. The trash button deletes the whole folder through the standard confirmation dialog — which shows the byte total and honors the app delete mode.",
            ]),
        ],
        key_items=[
            ("duplicatesSection(_:)", "Fingerprint-based duplicate groups with keep-first marking"),
            ("installsSection(_:)", "Homebrew + source installs with build/ sizes and versions"),
            ("modelsSection(_:)", "Per-store model listing with reveal + delete"),
        ],
    ),
    dict(
        slug="settingsview-swift", title="Sources/MacSpaces/Views/SettingsView.swift", category="core",
        path="Sources/MacSpaces/Views/SettingsView.swift", lines=149, lang="Swift", status="CORE", pkg="MacSpaces",
        phase="v1.0", spec_refs=[], tested_by="", related=["trashservice-swift", "llamaauditor-swift", "appmodel-swift"],
        lead=[
            "The Settings scene: default delete behavior, custom GGUF folder management with a native folder picker, and source-scan-root editing. Everything persists to UserDefaults and takes effect on the next audit — no restart needed.",
        ],
        sections=[
            ("Persistence model", [
                "Delete mode is a @AppStorage on the DeletionMode raw string, the same key TrashService reads — one source of truth. Folder lists don't survive AppStorage directly, so they are stored as newline-joined strings under customGGUFFolders and sourceScanRoots; AppModel and LlamaAuditor read those keys, falling back to the LlamaAuditor.default* constants when unset.",
                "The folder picker uses .fileImporter with allowedContentTypes: [.folder]; picked paths inside the home directory are stored tilde-relative for portability across machines. Source roots accept typed entries ('~/code' style); bare names get a tilde prefix automatically. Both lists have restore-defaults buttons, and the footer notes the Full Disk Access recommendation.",
            ]),
        ],
        key_items=[
            ("@AppStorage(\"deleteMode\")", "Same key as TrashService.deleteMode"),
            ("fileImporter [.folder]", "Native multi-folder picker with tilde-relative storage"),
            ("addSourceRoot()", "Bare names auto-prefixed with ~/, deduplicated"),
        ],
    ),
]
