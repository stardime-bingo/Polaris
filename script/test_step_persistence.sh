#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p build
swiftc -suppress-warnings -framework AppKit -framework SwiftUI -framework Carbon -framework EventKit \
  Docket/Models/*.swift \
  Docket/Services/Store.swift Docket/Services/RemindersSync.swift \
  Docket/Services/GoalBoardRules.swift Docket/Services/GoalImportPlan.swift \
  Docket/Services/GoalDateParser.swift Docket/Services/DateParser.swift Docket/Services/DueDateFormatter.swift \
  tests/StoreStepTests.swift -o build/StoreStepTests
build/StoreStepTests
