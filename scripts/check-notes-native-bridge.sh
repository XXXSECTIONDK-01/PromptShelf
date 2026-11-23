#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
task_bundle="$task_root/.build/NotesNativeBridgeChecks.app"
mkdir -p "$task_bundle/Contents/MacOS" "$task_bundle/Contents/Resources"
python3 - "$task_bundle" <<'PY'
from pathlib import Path
import plistlib, sys
contents = Path(sys.argv[1]) / 'Contents'
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'studio.promptshelf.native-bridge-check',
    'CFBundleName': 'NotesNativeBridgeChecks', 'CFBundleExecutable': 'NotesNativeBridgeChecks',
    'CFBundlePackageType': 'APPL', 'NSPrincipalClass': 'NSApplication',
    'OSAScriptingDefinition': 'Notes.sdef', 'NSAppleScriptEnabled': True, 'LSUIElement': True
}))
# Public dictionary only. Does not read the Notes app's user data or launch Notes.
(contents / 'Resources/Notes.sdef').write_bytes(Path('/System/Applications/Notes.app/Contents/Resources/Notes.sdef').read_bytes())
PY
swiftc -module-cache-path .build/ModuleCache Tests/NotesNativeBridgeChecks/main.swift -o "$task_bundle/Contents/MacOS/NotesNativeBridgeChecks"
"$task_bundle/Contents/MacOS/NotesNativeBridgeChecks" "$task_root/Resources/NotesBridge.js"
