# Meta
*repo plumbing*

- **[Package.swift](../docs/package-swift.html)** — `Package.swift` (27 lines): Three targets, one dependency direction: MacSpacesCore (library) ← MacSpaces (app executable) and ← macspaces-tests (test executable). Platforms: macOS 13. Tools: 5.9. Zero externa
- **[scripts/build-app.sh](../docs/build-app-sh.html)** — `scripts/build-app.sh` (85 lines): Turns the SwiftPM build into a double-clickable .app: release build → Contents/{MacOS,Resources} assembly → Info.plist → generated icon → ad-hoc signature. Encodes every toolchain 
- **[scripts/make-icon.swift](../docs/make-icon-swift.html)** — `scripts/make-icon.swift` (115 lines): Generates AppIcon.icns at build time with zero assets in the repo: a Swift script draws the icon with CoreGraphics — blue→teal gradient rounded square, white usage ring at 72%, a s
- **[README.md](../docs/readme-md.html)** — `README.md` (78 lines): The repository front door: what the app does, the safety model, build/run instructions, permissions guidance, and the Ollama custom-path caveat. Points at this wiki and USER_GUIDE.
