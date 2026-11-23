# Contributing to PromptShelf

For a bug report, describe the expected behavior, what happened, and the smallest set of steps that reproduces it. Include the app version, macOS version, and Mac chip. Use sample prompts in screenshots and attached files.

For a pull request, describe the user-facing change and how you verified it. Changes to the library format should account for existing libraries and backups. Changes to the quick panel should preserve keyboard navigation, focus handling, and the distinction between filling a draft and sending it.

## Build and check

From the repository root, use an Apple toolchain with the macOS 26 SDK. The deployment target is macOS 14.

```sh
swift build --disable-sandbox --scratch-path .build --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/ModuleCache
.build/debug/PromptCoreChecks
bash scripts/check-ui-layout.sh
```

Use `.build/debug/PromptActionChecks` for quick panel actions and clipboard payloads, `.build/debug/StorageChecks` for data changes, and `.build/debug/NotesBridgeChecks` for Notes bridge changes. The layout checks use a temporary library, and clipboard checks use a named test pasteboard. A Notes integration report should state which operations were tested on a real macOS account.

Three modules separate library logic (`PromptCore`), reusable native controls (`PromptUI`), and the app and system integration (`PromptShelf`). Resources are bundled by `scripts/build-app.sh` and the DMG is assembled by `scripts/build-dmg.sh`.
