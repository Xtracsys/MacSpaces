# MacSpaces — User Guide

A native macOS app that monitors disk usage and reclaims space, with dedicated
audits for **Ollama** model stores and **llama.cpp** installs/models. Everything
it deletes goes to the Trash by default.

---

## 1. Install & launch

```sh
./scripts/build-app.sh            # → build/MacSpaces.app
./scripts/build-app.sh --install  # → /Applications/MacSpaces.app
open build/MacSpaces.app
```

| Requirement | Detail |
|---|---|
| macOS | 13 (Ventura) or newer |
| Architecture | Apple Silicon (build Intel/universal with `swift build -c release --arch arm64 --arch x86_64`) |
| Dependencies | None — single self-contained bundle |

**First launch on a non-build machine:** Gatekeeper may warn because the app is
ad-hoc signed. Fix once with:

```sh
xattr -cr /Applications/MacSpaces.app
```

or use System Settings → Privacy & Security → *Open Anyway*.

---

## 2. The four tabs

### Dashboard

The startup volume's usage ring (percent used, used/free/total), refreshed
every 30 seconds. Two audit summary cards — **Ollama** and **llama.cpp** —
show reclaimable space once audited, with buttons to run the audit and jump to
the tab. After your first disk scan, a chart of the eight largest folders
appears with a jump link into Disk Usage.

The **menu bar** shows a live readout (e.g. `34% free · 1.2 TB`) with quick
access to every mounted volume, Settings, and Quit.

### Ollama

Press *Audit Ollama* (or just open the tab — the first audit runs
automatically).

**What you'll see:**

- **Header cards** — model count and total size, orphaned-blob count and
  reclaimable bytes, the `~/.ollama` home size, and a **Running/Stopped** badge
  for the Ollama server.
- **Orphaned Blobs** — files in `~/.ollama/models/blobs/` that **no manifest
  references**. These are pure waste (interrupted pulls, half-deleted models)
  and safe to remove. Tick individual blobs or clean them all; cleanup is
  **always Trash-only**.
- **Models** — every manifest (`registry/ns/name:tag`) with:
  - *total size* — all blobs it references,
  - *unique size* — blobs no other model uses (what actually disappears if you
    delete it),
  - *shared* badge — layers reused across models,
  - a red *missing blobs* badge if a manifest references files that don't exist
    (integrity problem).
  Delete a model to trash its manifest + unique blobs; **shared layers are
  never removed**.
- **~/.ollama Footprint** — sizes of `logs/`, `backup/`, `cache/`, keys, etc.

> If the server shows **Running**, restart Ollama after cleanup so it picks up
> the changes.

### llama.cpp

- **Installations** — Homebrew packages (`llama-cli`… resolved to the Cellar,
  with version) and source checkouts found in your scan roots, including the
  size of `build/` artifacts and a `git describe` version.
- **Duplicate GGUFs** — models identical by content fingerprint (size + hash of
  first/last 256 KB). One click trashes all but one copy of each group.
- **Models by Location** — grouped by source:
  - *llama.cpp cache* — `~/.cache/llama.cpp` (models fetched via
    `llama-server -hf`)
  - *HuggingFace cache* — `~/.cache/huggingface/hub`
  - *Custom folder* — folders you add (default: `~/.ollama/models/ggufs`)

### Disk Usage

- **Scan Home Folder** (fast) or **Scan Entire Disk** (minutes; confirmed
  first). Live progress shows items, bytes, and the current path — Cancel
  stops cleanly.
- **Folder Tree** — sorted by size, click to drill down, right-click any item
  for *Reveal in Finder* or *Move to Trash*. Deleting updates the tree
  instantly (ancestor sizes shrink) without a rescan.
- **Largest Files** — the 150 biggest files with proportional bars.

---

## 3. Deleting things safely

| Action | Goes to | Notes |
|---|---|---|
| Any file/folder (Disk tab, context menu) | Trash (default) | Confirmation dialog shows name + size |
| Orphaned Ollama blobs | **Always Trash** | Even if permanent mode is on |
| A single Ollama model | Trash (default) | Manifest + unique blobs only; shared layers kept |
| Duplicate GGUFs | Trash (default) | Keeps the first copy of each group |

Change the default in **Settings** (Cmd-, or menu bar → Settings…):
*Move to Trash (recommended)* vs *Delete Permanently*. Permanent mode always
asks twice — the dialog offers a "Move to Trash Instead" escape hatch.

A feedback line at the bottom of the window reports every batch
(`Moved to Trash 3 items.` / failures with the reason).

---

## 4. Settings

- **Delete behavior** — trash vs permanent default.
- **Custom GGUF Folders** — folders scanned recursively for `*.gguf`; add via
  the native folder picker, stored `~/`-relative.
- **Source Scan Roots** — folders searched (3 levels deep) for llama.cpp
  checkouts. Defaults: `~/llama.cpp`, `~/src`, `~/code`, `~/Projects`, `~/dev`,
  `~/Developer`.

Changes take effect on the **next audit** — no restart needed.

---

## 5. Troubleshooting

**Sizes look incomplete / lock icons appear.**
The scan hit permission-denied folders. Grant Full Disk Access: System
Settings → Privacy & Security → Full Disk Access → add MacSpaces (or Terminal,
if running via `swift run`), then rescan.

**My Ollama models aren't showing.**
The auditor reads `~/.ollama/models` only. A Finder-launched app doesn't
inherit your shell's environment, so a custom `OLLAMA_MODELS` path isn't
visible — keep the default location or symlink it.

**App shows "damaged" on another Mac.**
Quarantine flag + ad-hoc signature. Run `xattr -cr` on the app (see §1), or
distribute notarized builds.

**A scan is slow.**
Full-disk scans traverse every reachable file. Use *Scan Home Folder* for
day-to-day work; reserve the full scan for periodic deep audits.

---

## 6. Learn more

- **Project wiki** — `wiki/index.html` (open in a browser): per-file
  documentation, architecture overview, and this guide as a tabbed article.
- **README.md** — build instructions and the safety model summary.
- **Regenerate the wiki** after code changes:
  `python3 ~/.agents/skills/code-wiki-generator/scripts/generate_wiki.py --source . --out wiki wiki-src`
