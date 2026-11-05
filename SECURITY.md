# Security Policy

## Reporting a vulnerability

Do not open public issues for security problems.

Email **josh@xtracsys.com** with details, reproduction steps, and
affected commits. You will receive an acknowledgement within 72 hours.
Please avoid public disclosure until a fix is released; we will credit
reporters in the release notes unless you prefer otherwise.

## Scope

MacSpaces is a local-only disk utility that reads untrusted filesystem
content by design — it scans arbitrary directories, parses binary model
files, and deletes user-selected paths. In scope:

- The GGUF header parser (`Sources/MacSpacesCore/Scanners/GGUFMeta.swift`):
  malformed headers, oversized lengths, arithmetic overflow in the byte
  reader
- The ignore-rule engine
  (`Sources/MacSpacesCore/Services/IgnoreRules.swift`): regex compilation of
  user-supplied globs, catastrophic backtracking, pattern-injection edge
  cases
- The deletion paths (`Sources/MacSpacesCore/Services/TrashService.swift`,
  delete verification in `AppModel`): root/home guards, TOCTOU between audit
  and deletion, symlink handling in trash and reveal
- Shell-out boundaries (`git describe` in `LlamaAuditor`, `tmutil` /
  `launchctl` / `osascript` in `TMSnapshots` / `ScheduledAudit`): argument
  construction from scanned paths
- Fixed-path writes (`ScheduledAudit`): report and launchd-plist targets,
  symlink-following

Out of scope: anything requiring the attacker to already control the
machine or the user's account.

## Design guarantees security researchers should test

- The app makes no network connections of any kind — no telemetry, no
  update checks, no downloads. Verified by inspection: zero URLSession /
  Network framework usage.
- Every shell-out uses fixed, absolute tool paths with a fixed argument
  list; no shell interpreter is involved.
- All destructive operations default to moving items to the Trash;
  permanent deletion is opt-in and always confirmed. Ollama orphan cleanup
  re-verifies reference status at deletion time.
- Filesystem roots and the home directory are refused as delete targets.
- Fixed-path writes (audit report, launchd plist) refuse symlinked targets.

## Known limitations

- The app is not sandboxed: full-disk scanning requires broad filesystem
  read access, and the same access applies to its delete operations (always
  user-initiated and confirmed).
- Builds are ad-hoc signed unless notarized via `scripts/notarize.sh`;
  distribute notarized builds to avoid Gatekeeper bypass prompts for
  recipients.
