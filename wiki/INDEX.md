# MacSpaces Reference — Wiki Index

> Generated 2026-10-30 22:57 UTC · 30 articles · data: `wiki_data.json`


## How to edit this wiki

1. `wiki_data.json` is the canonical content — always edit it first.

2. Run `python3 wikiupdate.py` to re-embed it into `index.html`.

3. Or regenerate everything: `python3 generate_wiki.py --source <repo> --out . <content_dir>`.


## Articles


### Overviews
*orientation*

| # | article | file | lines | status |
|---|---------|------|-------|--------|
| 01 | (system) | `(system)` | — | SPEC |
| 02 | (guide) | `(guide)` | — | SPEC |

### Core
*the meat*

| # | article | file | lines | status |
|---|---------|------|-------|--------|
| 01 | Models.swift | `Sources/MacSpacesCore/Models/Models.swift` | 499 | CORE |
| 02 | DiskScanner.swift | `Sources/MacSpacesCore/Scanners/DiskScanner.swift` | 200 | CORE |
| 03 | OllamaAuditor.swift | `Sources/MacSpacesCore/Scanners/OllamaAuditor.swift` | 290 | CORE |
| 04 | LlamaAuditor.swift | `Sources/MacSpacesCore/Scanners/LlamaAuditor.swift` | 336 | CORE |
| 05 | GGUFMeta.swift | `Sources/MacSpacesCore/Scanners/GGUFMeta.swift` | 201 | CORE |
| 06 | XcodeCachesAuditor.swift | `Sources/MacSpacesCore/Scanners/XcodeCachesAuditor.swift` | 77 | CORE |
| 07 | AppModel.swift | `Sources/MacSpacesCore/Services/AppModel.swift` | 335 | CORE |
| 08 | IgnoreRules.swift | `Sources/MacSpacesCore/Services/IgnoreRules.swift` | 110 | CORE |
| 09 | WatchService.swift | `Sources/MacSpacesCore/Services/WatchService.swift` | 73 | CORE |
| 10 | ScheduledAudit.swift | `Sources/MacSpacesCore/Services/ScheduledAudit.swift` | 184 | CORE |
| 11 | TMSnapshots.swift | `Sources/MacSpacesCore/Services/TMSnapshots.swift` | 68 | CORE |
| 12 | TrashService.swift | `Sources/MacSpacesCore/Services/TrashService.swift` | 38 | CORE |
| 13 | VolumeMonitor.swift | `Sources/MacSpacesCore/Services/VolumeMonitor.swift` | 49 | CORE |
| 14 | MacSpacesApp.swift | `Sources/MacSpaces/MacSpacesApp.swift` | 124 | CORE |
| 15 | Components.swift | `Sources/MacSpaces/Views/Components.swift` | 141 | CORE |
| 16 | ContentView.swift | `Sources/MacSpaces/Views/ContentView.swift` | 89 | CORE |
| 17 | DashboardView.swift | `Sources/MacSpaces/Views/DashboardView.swift` | 283 | CORE |
| 18 | DiskTreeView.swift | `Sources/MacSpaces/Views/DiskTreeView.swift` | 311 | CORE |
| 19 | OllamaView.swift | `Sources/MacSpaces/Views/OllamaView.swift` | 381 | CORE |
| 20 | LlamaView.swift | `Sources/MacSpaces/Views/LlamaView.swift` | 379 | CORE |
| 21 | CachesView.swift | `Sources/MacSpaces/Views/CachesView.swift` | 261 | CORE |
| 22 | SettingsView.swift | `Sources/MacSpaces/Views/SettingsView.swift` | 266 | CORE |

### Tests
*verification*

| # | article | file | lines | status |
|---|---------|------|-------|--------|
| 01 | Runner.swift | `Tests/MacSpacesTestRunner/Runner.swift` | 515 | TEST |

### Meta
*repo plumbing*

| # | article | file | lines | status |
|---|---------|------|-------|--------|
| 01 | Package.swift | `Package.swift` | 34 | META |
| 02 | build-app.sh | `scripts/build-app.sh` | 82 | META |
| 03 | make-icon.swift | `scripts/make-icon.swift` | 114 | META |
| 04 | README.md | `README.md` | 95 | META |
| 05 | notarize.sh | `scripts/notarize.sh` | 64 | META |
