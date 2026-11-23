#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
swift build -c release --product InputProbe --disable-sandbox --scratch-path .build --cache-path .build/cache -Xswiftc -module-cache-path -Xswiftc .build/ModuleCache
task_binary_dir="$(swift build -c release --disable-sandbox --scratch-path .build --cache-path .build/cache --show-bin-path)"
task_probe="$task_root/.build/InputProbe.app"
mkdir -p "$task_probe/Contents/MacOS"
cp "$task_binary_dir/InputProbe" "$task_probe/Contents/MacOS/InputProbe"
cat > "$task_probe/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>InputProbe</string>
<key>CFBundleDisplayName</key><string>词屿填入测试</string>
<key>CFBundleIdentifier</key><string>studio.promptshelf.inputprobe</string>
<key>CFBundleExecutable</key><string>InputProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$task_probe"
echo "Built: $task_probe"
