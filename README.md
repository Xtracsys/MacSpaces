# MacSpaces

A native macOS app (SwiftUI) for monitoring and reclaiming disk space, with
purpose-built audits for local AI tooling:

- **Ollama** — parses every manifest in `~/.ollama/models/manifests`, cross-references
  them against `~/.ollama/models/blobs`, and finds **orphaned blobs** (files no manifest
  references, e.g. left behind by interrupted pulls or deleted models). Shows per-model
  sizes with shared-layer attribution, the full `~/.ollama` footprint, and whether the
  Ollama server is running before you delete anything.
- **llama.cpp** — detects Homebrew installs (`/opt/homebrew`, `/usr/local`), source
  checkouts and local builds in your dev folders (including `build/` artifact size),
  the llama.cpp download cache (`~/.cache/llama.cpp`), the HuggingFace hub cache
  (`~/.cache/huggingface/hub`), and any custom folders you add. Loose `*.gguf` files
  are deduped by a content fingerprint (size + head/tail hash).
- **Disk usage** — parallel tree scanner for your home folder or the whole disk,
  drill-down by folder, top-150 largest files, delete or reveal any node.
- **Menu bar** — live free-space readout for the startup volume.

## Safety model

Deletions default to **Move to Trash** (configured in Settings; permanent deletion is
available and always asks for confirmation). Ollama orphan cleanup is always Trash-only.
Shared model layers are never deleted when removing a single model — its manifest plus
blobs referenced *only* by that model go to the Trash.

The app also warns (and shows a "Running" badge) if the Ollama server process is alive,
since deletions take effect after a server restart.

## Building

Requires macOS 13+ and Swift 5.9+ (Command Line Tools are sufficient — no Xcode IDE needed).

```sh
swift build                # debug build
swift test                 # unit tests (orphan detection, dedupe, tree ops)
./scripts/build-app.sh     # release build → build/MacSpaces.app
./scripts/build-app.sh --install   # …and copy to /Applications
```

Launch:

```sh
open build/MacSpaces.app
```

## Permissions

A full-disk scan needs **Full Disk Access** for terminal-driven builds:
*System Settings → Privacy & Security → Full Disk Access* — add Terminal (when running
`swift run`) or the MacSpaces binary itself. Without it, protected folders
(`~/Library/Mail`, etc.) show a lock icon and are excluded from sizes rather than failing.

## Ollama notes

The auditor reads the default model store at `~/.ollama`. If you run Ollama with a
custom `OLLAMA_MODELS` path, the tool won't see it (the app reads the standard home,
since it doesn't inherit your shell's environment). Everything else — manifests,
blobs, footprint of `logs/` etc. — is sized and reported.

## Documentation

- **[USER_GUIDE.md](USER_GUIDE.md)** — full walkthrough of every tab, the safety model, and troubleshooting.
- **[Project wiki](wiki/index.html)** — tabbed per-file documentation (open `wiki/index.html` in a browser).
- Regenerate the wiki after code changes:
  `python3 ~/.agents/skills/code-wiki-generator/scripts/generate_wiki.py --source . --out wiki wiki-src`

## Project layout

```
Sources/MacSpaces/
  MacSpacesApp.swift        app entry, menu bar extra, settings scene
  Models/Models.swift       value types shared by scanners and views
  Scanners/
    DiskScanner.swift       bounded-concurrency directory tree scanner
    OllamaAuditor.swift     manifest/blob cross-reference, orphan + footprint report
    LlamaAuditor.swift      brew/source install discovery, GGUF dedupe, cache scans
  Services/
    AppModel.swift          central state, scan/audit orchestration, deletions
    TrashService.swift      trash vs permanent delete, Finder reveal
    VolumeMonitor.swift     periodic volume capacity polling
  Views/                    Dashboard, DiskUsage tree, Ollama, llama.cpp, Settings
Tests/MacSpacesTests/       fixture-based tests for the audit logic
scripts/                    .app packaging + icon generation
```
