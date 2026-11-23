#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [[ "${1:-}" != "--skip-build" ]]; then
    bash scripts/build-app.sh
fi
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
task_app="$task_root/dist/PromptShelf.app"
task_built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
[[ "$task_version" == "$task_built_version" ]] || { echo "Version mismatch; rebuild the app." >&2; exit 1; }
codesign --verify --deep --strict "$task_app"
mkdir -p "$task_root/.build" "$task_root/dist"
task_staging="$(mktemp -d "$task_root/.build/dmg.XXXXXX")"
trap 'rm -rf "$task_staging"' EXIT
ditto "$task_app" "$task_staging/PromptShelf.app"
ln -s /Applications "$task_staging/Applications"
cp Resources/安装说明.md "$task_staging/安装说明.md"
task_dmg="$task_root/dist/PromptShelf-$task_version-macOS.dmg"
hdiutil create -volname "词屿 $task_version" -srcfolder "$task_staging" -format UDZO -imagekey zlib-level=9 -fs HFS+ -ov "$task_dmg"
hdiutil verify "$task_dmg"
echo "Built: $task_dmg"
