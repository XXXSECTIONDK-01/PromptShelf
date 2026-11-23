#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
swift build -c release --disable-sandbox --scratch-path .build --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/ModuleCache
task_binary_dir="$(swift build -c release --disable-sandbox --scratch-path .build --cache-path .build/cache --show-bin-path)"
task_app="$task_root/dist/PromptShelf.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_binary_dir/PromptShelf" "$task_app/Contents/MacOS/PromptShelf"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
cp Resources/NotesBridge.js "$task_app/Contents/Resources/NotesBridge.js"
cp Resources/AppIconArtwork.png "$task_app/Contents/Resources/AppIconArtwork.png"
swift -module-cache-path .build/ModuleCache scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$task_app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier studio.promptshelf.mac "$task_app"
ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_root/dist/PromptShelf-macOS.zip"
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
cp "$task_root/dist/PromptShelf-macOS.zip" "$task_root/dist/PromptShelf-$task_version-macOS.zip"
echo "Built: $task_app"
