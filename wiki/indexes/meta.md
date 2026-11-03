# Meta
*repo plumbing*

- **Package.swift** — `Package.swift` (34 lines): Three targets, one dependency direction: MacSpacesCore (library) ← MacSpaces (app) and ← macspaces-tests. Platforms: macOS 13. Tools: 5.9. Zero external dependencies.
- **build-app.sh** — `scripts/build-app.sh` (82 lines): Turns the SwiftPM build into a double-clickable .app. Encodes every toolchain workaround discovered during bring-up so a fresh clone builds with one command.
- **make-icon.swift** — `scripts/make-icon.swift` (114 lines): Generates AppIcon.icns at build time with zero repo assets: CoreGraphics draws the gradient rounded square, a white usage ring at 72%, and a bar-chart glyph row; the full iconset P
- **README.md** — `README.md` (130 lines): The repository front door: feature pillars (including all ten v1.1 additions), the safety model, build instructions with the CLT caveat, permissions guidance, the Ollama 0.34 dual-
- **notarize.sh** — `scripts/notarize.sh` (64 lines): The distribution gate: Developer ID signing, notarization via notarytool, and ticket stapling. Ad-hoc-signed builds trigger Gatekeeper on other Macs ('damaged' on recent macOS); a 
