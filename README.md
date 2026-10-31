# MacSpaces

<p align="center">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-blue.svg"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey">
  <img alt="Language" src="https://img.shields.io/badge/swift-5.9-orange">
</p>

A native macOS app (SwiftUI) for monitoring and reclaiming disk space, with
purpose-built audits for local AI tooling. Open source under the Apache 2.0
license, maintained by **Xtracsys LLC**.

- **Ollama** — parses every manifest (both the classic `manifests/` tree and the
  new Ollama 0.34+ `manifests-v2/` layout), cross-references them against
  `~/.ollama/models/blobs`, and finds **orphaned blobs**. Orphan cleanup
  **re-verifies against a fresh audit at deletion time**, so blobs claimed by a
  new pull in the meantime are skipped. Shows per-model sizes with shared-layer
  attribution, a **version manager** grouping multi-tag models by base name,
  integrity reporting for missing blobs, and the full `~/.ollama` footprint.
- **llama.cpp & friends** — Homebrew installs, source checkouts with build/
  artifact sizes, the llama.cpp download cache, the HuggingFace hub cache,
  **LM Studio, Jan, and GPT4All** stores, plus custom folders. GGUF files are
  deduped by content fingerprint and **GGUF headers are parsed** for
  architecture, quantization, and context length.
- **Caches & Snapshots** — Xcode DerivedData/Archives/DeviceSupport, simulator
  and SwiftPM caches, and **APFS local Time Machine snapshots** (list + thin
  via `tmutil`).
- **Disk usage** — parallel whole-disk tree scanner (with a deadlock-free
  bounded task pool), drill-down by folder, top-150 largest files, delete or
  reveal any node. **Glob ignore rules** apply to scans and GGUF collection.
- **Monitoring** — menu bar free-space readout, **folder watcher** with
  threshold alerts on the Dashboard, and an optional **weekly launchd audit**
  that posts a reclaimable-space digest notification.
- **CLI companion** — `MacSpaces --audit-json` prints a machine-readable report
  to stdout; `MacSpaces --scheduled-audit` writes the report and posts the
  digest (used by the launchd agent).

## Safety model

Deletions default to **Move to Trash** (permanent deletion is opt-in in
Settings and always asks twice). Ollama orphan cleanup is **always Trash-only**
and re-verified. Shared model layers are never deleted when removing a single
model. Cache cleanup and snapshot thinning are Trash-safe / purgeable-space
operations respectively.

## Building

Requires macOS 13+ and Swift 5.9+ (Command Line Tools are sufficient).

```sh
swift run --scratch-path .build/tests macspaces-tests   # 100-assertion suite
./scripts/build-app.sh                                  # → build/MacSpaces.app
./scripts/build-app.sh --install                        # → /Applications
```

The build script auto-detects the missing `SwiftUIMacros` plugin in this CLT
install and falls back to the 26.5 SDK. With full Xcode installed it uses the
default toolchain.

## Distributing to other Macs

```sh
./scripts/build-app.sh --universal --dmg   # arm64+x86_64 fat binary + drag-to-install DMG
./scripts/notarize.sh                      # Developer ID sign + notarize (needs Apple Developer credentials)
```

`--dmg` produces `build/MacSpaces.dmg` (drag MacSpaces.app onto the
Applications link). Ad-hoc-signed builds trigger Gatekeeper on other machines —
recipients can clear the flag once with
`xattr -cr /Applications/MacSpaces.app`, or you notarize for a clean
double-click install. See `scripts/notarize.sh` for the credential setup.

## Permissions

Full-disk scans need **Full Disk Access** (System Settings → Privacy &
Security → Full Disk Access). Without it, protected folders show a lock icon
and are excluded from sizes rather than failing.

## Ollama notes

The auditor reads `~/.ollama/models` (both `manifests/` and `manifests-v2/`,
plus the `metadata/` directory for context). A Finder-launched app does not
inherit your shell environment, so a custom `OLLAMA_MODELS` path is not
visible — keep the default location or symlink it.

## Documentation

- **[USER_GUIDE.md](USER_GUIDE.md)** — full walkthrough of every tab, the safety model, and troubleshooting.
- **[Project wiki](wiki/index.html)** — tabbed per-file documentation (open `wiki/index.html` in a browser).
- Regenerate the wiki after code changes:
  `python3 ~/.agents/skills/code-wiki-generator/scripts/generate_wiki.py --source . --out wiki wiki-src`

## Project layout

```
Sources/MacSpacesCore/
  Models/Models.swift       shared value types (incl. reports, caches, snapshots)
  Scanners/
    DiskScanner.swift       bounded-concurrency tree scanner (deadlock-free)
    OllamaAuditor.swift     manifest/blob cross-reference, orphans, version groups
    LlamaAuditor.swift      installs + 6 model-store sources, GGUF dedupe
    GGUFMeta.swift          GGUF header parser (arch, quant, context length)
    XcodeCachesAuditor.swift DerivedData/Archives/SwiftPM caches
  Services/
    AppModel.swift          central state, scan/audit orchestration, deletions
    TrashService.swift      trash vs permanent delete, Finder reveal
    VolumeMonitor.swift     periodic volume capacity polling
    IgnoreRules.swift       glob ignore patterns
    WatchService.swift      folder size threshold alerts
    TMSnapshots.swift       tmutil list/thin for local APFS snapshots
    ScheduledAudit.swift    headless audit, JSON reports, launchd weekly digest
Sources/MacSpaces/          @main scene + SwiftUI views (incl. CachesView)
Tests/MacSpacesTestRunner/  macro-free 86-assertion suite
scripts/                    .app packaging + icon generation
wiki-src/                   wiki content modules (regenerate with the command above)
```

## License

Copyright 2026 **Xtracsys LLC**. Licensed under the
[Apache License, Version 2.0](LICENSE). Contributions are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the build/test expectations and the
SPDX header convention.
