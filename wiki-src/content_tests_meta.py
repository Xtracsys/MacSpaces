ARTICLES = [
    dict(
        slug="runner-swift", title="Tests/MacSpacesTestRunner/Runner.swift", category="tests",
        path="Tests/MacSpacesTestRunner/Runner.swift", lines=292, lang="Swift", status="TEST", pkg="macspaces-tests",
        phase="v1.0", spec_refs=[], tested_by="", related=["ollamaauditor-swift", "llamaauditor-swift", "models-swift"],
        lead=[
            "41 assertions across four suites, run by a hand-rolled harness that exits non-zero on failure. The harness exists because this machine's Command Line Tools ship neither the macOS XCTest framework (swift test fails with 'unable to resolve module dependency: XCTest') nor the Swift Testing macro plugin — the same toolchain gap that forced the 26.5 SDK fallback for SwiftUI macros.",
        ],
        sections=[
            ("Harness", [
                "TestRecorder collects per-assertion failures with file/line and counts passes; expectEqual is a thin Equatable wrapper that prints both values in the failure line. @main TestMain runs the suites, prints 'Passed assertions: N' and 'ALL TESTS PASSED' or the numbered failure list, and exits 1 on any failure. Run with: swift run --scratch-path .build/tests macspaces-tests (the separate scratch path lets tests build under the default SDK while the SwiftUI app builds under 26.5).",
                "The test target depends only on MacSpacesCore and uses @testable import MacSpacesCore — legal because SwiftPM passes -enable-testing in debug builds. A plain import compiles but makes every internal Core type invisible, which produced a very confusing 'cannot find DiskNode' phase during bring-up.",
            ]),
            ("OllamaAuditTests — the orphan engine", [
                "Fixtures build a temp ~/.ollama with makeBlob (sizes in multiples of 4096 so APFS allocated size equals written size — the first run's 1000-byte blobs reported 4096 and broke every size assertion) and makeManifest writing real manifest JSON with config/layers digests.",
                "orphanDetectionAndSharedLayers is the core case: two manifests sharing one layer, one orphan blob. Asserts the orphan set and byte total, shared detection, model A's total (4096 + 4096 + 8192 = 16384), its unique size (12288), shared count (1), and model B's unique size of 0. This is the test that caught the sharedBlobDigests-before-population ordering bug. missingBlobsReported covers phantom digests; blobsUniqueToModel proves a shared layer is excluded from model deletion; processDetection writes our own pid to ollama.pid (must report running) and 'not-a-pid' (must not). Each test gets a fresh temp root — an early version shared one root and accumulated manifests across tests.",
                "Path comparisons resolve symlinks on both sides: FileManager.temporaryDirectory hands out /var/folders/... while enumerators return the resolved /private/var/folders/..., so raw URL equality silently failed. resolvingSymlinks via URL handles this.",
            ]),
            ("LlamaAuditTests and DiskTreeTests", [
                "LlamaAuditTests: prettyModelName (models--org--name → org/name), tilde expansion, duplicate detection (two identical payloads + one different file → exactly one group of two excluding the different file), and a custom-folder end-to-end audit. DiskTreeTests: removing() splices a file out of a two-level tree and shrinks both ancestor totals (asserts 100 remaining after removing a 500-byte file from a 600-byte tree — an early draft of the fixture put the file at the wrong path and the test accidentally passed with the broken implementation), largestFiles ordering, and all five shouldSkip rules including the root-prefix-only-at-'/' case.",
            ]),
        ],
        key_items=[
            ("TestRecorder / expectEqual", "Macro-free assertions with file:line failure reporting"),
            ("withTempRoot(_ body:)", "Fresh fixture root per test, cleaned up in defer"),
            ("swift run --scratch-path .build/tests macspaces-tests", "How to run the suite"),
        ],
    ),
    dict(
        slug="package-swift", title="Package.swift", category="meta",
        path="Package.swift", lines=27, lang="SwiftPM", status="META", pkg="",
        phase="v1.0", spec_refs=[], tested_by="", related=["runner-swift", "overview-architecture"],
        lead=[
            "Three targets, one dependency direction: MacSpacesCore (library) ← MacSpaces (app executable) and ← macspaces-tests (test executable). Platforms: macOS 13. Tools: 5.9. Zero external dependencies — everything is Foundation, AppKit, SwiftUI, and Charts.",
        ],
        sections=[
            ("Why the tests are an executableTarget", [
                "The obvious .testTarget failed twice on this toolchain: CLT lacks the macOS XCTest framework entirely, and the Swift Testing macro plugin is also missing. A plain executable target linking MacSpacesCore sidesteps both. The comment in the manifest documents the run command — swift run --scratch-path .build/tests macspaces-tests — including why the separate scratch path exists (tests build under the default 27.0 SDK, which is only toxic to SwiftUI macro expansion).",
            ]),
        ],
        key_items=[
            ("MacSpacesCore", "Library target: models, scanners, services — no SwiftUI"),
            ("MacSpaces", "GUI executable: @main + views; depends on Core"),
            ("macspaces-tests", "Macro-free harness executable; depends on Core"),
        ],
    ),
    dict(
        slug="build-app-sh", title="scripts/build-app.sh", category="meta",
        path="scripts/build-app.sh", lines=85, lang="bash", status="META", pkg="",
        phase="v1.0", spec_refs=["README.md"], tested_by="", related=["make-icon-swift", "overview-user-guide"],
        lead=[
            "Turns the SwiftPM build into a double-clickable .app: release build → Contents/{MacOS,Resources} assembly → Info.plist → generated icon → ad-hoc signature. Encodes every toolchain workaround discovered during bring-up so a fresh clone builds with one command.",
        ],
        sections=[
            ("SDK fallback", [
                "If libSwiftUIMacros.dylib is absent from the CLT plugin directory (a defect in the 27.0 Command Line Tools: the SDK's SwiftUI uses macros but the plugin ships missing) and the 26.5 SDK exists, the script exports SDKROOT to the 26.5 SDK before building. On a machine with full Xcode installed the check passes and the default SDK is used unchanged.",
                "The build step is swift build -c release --product MacSpaces — --product matters: a bare swift build also builds macspaces-tests, which needs -enable-testing and therefore fails in release. The binary path comes from --show-bin-path rather than guesswork.",
            ]),
            ("Bundle assembly", [
                "Writes Info.plist with CFBundleIdentifier com.macspaces.app, LSMinimumSystemVersion 13.0, public.app-category.utilities, NSHighResolutionCapable, and a CFBundleIconFile reference. Copies the executable, generates Resources/AppIcon.icns via the make-icon.swift script (failure is non-fatal and the icon plist key is deleted so no dangling reference remains), then clears extended attributes with xattr -cr before codesign --force --deep --sign - — the xattr step is load-bearing: Finder metadata detritus makes ad-hoc signing fail with 'resource fork, Finder information, or similar detritus not allowed'.",
                "--install copies the finished bundle to /Applications, replacing any previous copy. The script prints the launch command (open build/MacSpaces.app) on success.",
            ]),
        ],
        key_items=[
            ("./scripts/build-app.sh [--install]", "Build the bundle; optionally install to /Applications"),
            ("SDKROOT fallback", "Auto-detects the missing SwiftUIMacros plugin, pins 26.5 SDK"),
            ("xattr -cr before codesign", "Prevents Finder-detritus signature failures"),
        ],
    ),
    dict(
        slug="make-icon-swift", title="scripts/make-icon.swift", category="meta",
        path="scripts/make-icon.swift", lines=115, lang="Swift (script)", status="META", pkg="",
        phase="v1.0", spec_refs=[], tested_by="", related=["build-app-sh"],
        lead=[
            "Generates AppIcon.icns at build time with zero assets in the repo: a Swift script draws the icon with CoreGraphics — blue→teal gradient rounded square, white usage ring at 72%, a small bar-chart glyph row — writes the full .iconset PNG matrix, and shells out to iconutil.",
        ],
        sections=[
            ("Details", [
                "drawIcon(size:) renders into a CGContext per size (16 through 1024); the ring is two arcs over a 25%-alpha track with round caps, and the bar chart sits in the lower center. The size→filename switch covers the complete standard iconset naming (icon_16x16.png through icon_512x512@2x.png). PNG encoding goes through NSBitmapImageRep. iconutil -c icns compiles the iconset; failure exits non-zero so build-app.sh falls back to an icon-less bundle rather than shipping a broken resource.",
            ]),
        ],
        key_items=[
            ("drawIcon(size:) -> CGImage?", "Gradient tile + usage ring + bars, resolution independent"),
            ("iconset matrix + iconutil", "16–1024 px mapped to all required filenames"),
        ],
    ),
    dict(
        slug="readme-md", title="README.md", category="meta",
        path="README.md", lines=78, lang="Markdown", status="META", pkg="",
        phase="v1.0", spec_refs=[], tested_by="", related=["overview-user-guide", "overview-architecture"],
        lead=[
            "The repository front door: what the app does, the safety model, build/run instructions, permissions guidance, and the Ollama custom-path caveat. Points at this wiki and USER_GUIDE.md for the full walkthrough.",
        ],
        sections=[
            ("Coverage", [
                "Summarizes the three feature pillars (Ollama orphan audits, llama.cpp/GGUF management with dedupe, parallel disk scanning), the Trash-by-default safety model with the shared-layer guarantee, the CLT-only build path (scripts/build-app.sh, swift run for tests), Full Disk Access guidance for full scans, and the OLLAMA_MODELS limitation: the app reads ~/.ollama only, because a Finder-launched app does not inherit your shell's environment.",
            ]),
        ],
        key_items=[
            ("swift build / swift run --scratch-path .build/tests macspaces-tests", "Build and test entry points"),
            ("./scripts/build-app.sh --install", "One-command bundle + install"),
        ],
    ),
]
