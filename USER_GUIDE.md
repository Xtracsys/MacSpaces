# MacSpaces — User Guide (v1.1)

A native macOS app that monitors disk usage and reclaims space, with dedicated
audits for **Ollama**, **llama.cpp** and other local AI runtimes. Everything it
deletes goes to the Trash by default.

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
| Architecture | Apple Silicon (universal: `swift build -c release --arch arm64 --arch x86_64`) |
| Dependencies | None — single self-contained bundle |

**First launch on a non-build machine:** Gatekeeper may warn (ad-hoc signature).
Fix once with `xattr -cr /Applications/MacSpaces.app` or use
System Settings → Privacy & Security → *Open Anyway*.

**CLI companion:** the app binary doubles as a headless auditor:

```sh
/Applications/MacSpaces.app/Contents/MacOS/MacSpaces --audit-json | jq .
```

---

## 2. The five tabs

### Dashboard

Startup volume usage ring (refreshed every 30 s), audit summary cards for
**Ollama**, **llama.cpp**, and **Caches** — each with a one-click audit that
jumps to its tab — plus **Watched Folder Alerts** when a monitored folder grows
past its threshold, and a chart of the eight largest folders after your first
scan.

The **menu bar** shows live free space; its menu has volume details and a
**Quick clean** section: trash orphaned Ollama blobs or duplicate GGUFs
directly, once audits have run.

### Ollama

- **Orphaned Blobs** — files in `blobs/` that no manifest references. Cleanup
  is **always Trash-only** and **re-verified at deletion time**: each blob is
  checked against a fresh audit, and blobs claimed by a new pull since the
  on-screen audit are skipped. Tick individual blobs or clean all.
- **Models** — every manifest with total size, *unique* size (what actually
  disappears if you delete it), shared-layer and missing-blob badges, and a
  `quant` badge for quantization tags.
- **Version Groups** — base models pulled with multiple tags (e.g. Q4_K_M and
  Q8_0 of the same weights), newest first, with per-variant delete. Retire old
  quants you no longer run.
- **~/.ollama Footprint** — sizes of every top-level directory.

Both the classic `manifests/` tree and the new Ollama 0.34+ `manifests-v2/`
layout are read; the running-server badge reminds you to restart Ollama after
cleanup.

### llama.cpp

- **Installations** — Homebrew (with the real Cellar version) and source
  checkouts including `build/` artifact sizes and `git describe` versions.
- **Duplicate GGUFs** — identical files by content fingerprint (size + hash of
  first/last 256 KB); one click trashes all but one copy of each group.
- **Models by Location** — grouped by source: llama.cpp cache
  (`~/.cache/llama.cpp`), HuggingFace hub cache, **LM Studio**
  (`~/.lmstudio/models`), **Jan**, **GPT4All**, and your custom folders.
  Each GGUF row shows parsed header metadata: **architecture, quantization,
  context length**.

### Caches & Snapshots

- **Developer Caches** — Xcode DerivedData (per project), Archives, iOS Device
  Support, Simulator caches, SwiftPM caches. All rebuild automatically;
  cleanup goes to the Trash.
- **Local Time Machine Snapshots** — APFS snapshots on the startup disk, with
  a *Thin Snapshots* action that asks macOS to free up to 20 GB by deleting
  the oldest ones (purgeable space; backups on the TM drive are untouched).

### Disk Usage

- **Scan Home Folder** (fast) or **Scan Entire Disk** (minutes; confirmed
  first). Live progress shows items, bytes, and the current path.
- **Folder Tree** — sorted by size, click to drill down, right-click for
  *Reveal in Finder* / *Move to Trash*. Deleting updates the tree instantly.
- **Largest Files** — the 150 biggest files with proportional bars.
- **Ignore Rules** from Settings are honored during scans.

---

## 3. Deleting things safely

| Action | Goes to | Notes |
|---|---|---|
| Any file/folder (Disk tab) | Trash (default) | Confirmation shows name + size |
| Orphaned Ollama blobs | **Always Trash, re-verified** | Skips blobs newly referenced by pulls |
| A single Ollama model | Trash | Manifest + unique blobs only; shared layers kept |
| Duplicate GGUFs | Trash (default) | Keeps the first copy of each group |
| Developer caches | Always Trash | Rebuilt automatically by Xcode/SwiftPM |
| Local TM snapshots | n/a (system purge) | `tmutil thinlocalsnapshots` |

Change the default in **Settings** (Cmd-,): *Move to Trash (recommended)* vs
*Delete Permanently* — permanent mode always offers a "Move to Trash Instead"
escape hatch in the dialog.

---

## 4. Settings

- **Delete behavior** — trash vs permanent default.
- **Custom GGUF Folders** — recursive `*.gguf` scan targets (folder picker,
  stored `~/`-relative). An explicitly emptied list stays empty.
- **Source Scan Roots** — where to look for llama.cpp checkouts.
- **Ignore Rules** — glob patterns, one per line: `node_modules/`, `*.tmp`,
  `build`, `**` semantics documented inline. Applies to disk scans and GGUF
  collection.
- **Folder Watcher** — pick folders to monitor and a GB threshold; violations
  appear as Dashboard alerts (checked every 5 minutes).
- **Scheduled Audit** — toggle a launchd agent that runs the headless audit
  every Friday at 10:00 and posts a reclaimable-space notification.
- **Report Export** — save the full JSON audit report anywhere; or use
  `--audit-json` on the command line.

---

## 5. Troubleshooting

**Sizes look incomplete / lock icons.** Grant Full Disk Access to MacSpaces
(or Terminal when running via `swift run`), then rescan.

**My Ollama models aren't showing.** The auditor reads `~/.ollama/models`
only; a custom `OLLAMA_MODELS` path isn't visible to a Finder-launched app.

**App shows "damaged" on another Mac.** Run `xattr -cr` on the app, or
distribute notarized builds.

**Orphan count looks large.** Check the byte total — Ollama stores many small
config/tokenizer blobs per pull, so hundreds of tiny orphans are normal; the
reclaimable number is what matters.

**A scan is slow.** Use *Scan Home Folder* for daily work; full-disk scans are
periodic deep audits. Ignore rules can skip known-noisy trees.

---

## 6. Learn more

- **Project wiki** — `wiki/index.html`: per-file documentation and architecture.
- **Regenerate the wiki**: `python3 ~/.agents/skills/code-wiki-generator/scripts/generate_wiki.py --source . --out wiki wiki-src`
