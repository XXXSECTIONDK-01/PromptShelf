#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_sources=()
for task_file in Sources/PromptShelf/*.swift; do
  [[ "$task_file" == "Sources/PromptShelf/App.swift" ]] || task_sources+=("$task_file")
done
swiftc -parse-as-library -I .build/debug/Modules -module-cache-path .build/ModuleCache \
  "${task_sources[@]}" Tests/UILayoutChecks/main.swift \
  .build/debug/PromptCore.build/*.swift.o .build/debug/PromptUI.build/*.swift.o \
  -o .build/UILayoutChecks
.build/UILayoutChecks
