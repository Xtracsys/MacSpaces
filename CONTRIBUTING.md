# Contributing to MacSpaces

Thank you for considering a contribution! This project is Apache 2.0 licensed —
by submitting a pull request you agree your contribution is licensed under the
same terms (see LICENSE; the DCO-style sign-off in your commit message is
appreciated: `Signed-off-by: Your Name <you@example.com>`).

## Building

macOS 13+ with Swift 5.9+ — Command Line Tools are sufficient, Xcode is not.

```sh
swift run --scratch-path .build/tests macspaces-tests   # test suite
./scripts/build-app.sh                                  # → build/MacSpaces.app
./scripts/build-app.sh --dmg                            # + drag-to-Applications DMG
```

The build script pins an older SDK automatically when the installed Command
Line Tools lack the SwiftUI macro plugin; on a full Xcode install it just
works.

## Project layout

```
Sources/MacSpacesCore/    library: models, scanners, services (no SwiftUI)
Sources/MacSpaces/        app target: @main scene + SwiftUI views
Tests/MacSpacesTestRunner/ macro-free test harness (CLT lacks XCTest)
wiki-src/                 documentation content (regenerates wiki/)
```

## Ground rules

- **Every change needs a passing test run.** `swift run --scratch-path .build/tests macspaces-tests` must print ALL TESTS PASSED.
- **Deletions are the dangerous surface.** Any change to TrashService,
  OllamaAuditor (orphan detection, `blobsUniqueTo`), or the delete-verification
  paths in AppModel needs a fixture test covering the new behavior — these
  guards exist because real bugs reached them before.
- **New scanner outputs belong in `Models.swift`** as public value types with
  explicit initializers; scanners stay internal.
- **No third-party dependencies.** Apple frameworks only — this keeps the
  supply chain empty by design (see NOTICE).
- Match the existing comment style: comments state constraints the code cannot
  show, not narration.

## Source file headers

New source files should carry the Apache 2.0 SPDX header:

```swift
// Copyright 2026 Xtracsys LLC
// SPDX-License-Identifier: Apache-2.0
```

## Documentation

`wiki/` is generated from `wiki-src/content_*.py` — never hand-edit
`wiki/index.html` or `wiki/wiki_data.json`. After changing code or docs:

```sh
python3 ~/.agents/skills/code-wiki-generator/scripts/generate_wiki.py \
    --source . --out wiki --title "MacSpaces Reference" \
    --subtitle "Native macOS disk manager with AI-model audits" \
    --version <ver> wiki-src
```

## Releasing

```sh
./scripts/build-app.sh --universal --dmg       # fat binary + DMG
./scripts/notarize.sh                          # Developer ID + notarization
```
