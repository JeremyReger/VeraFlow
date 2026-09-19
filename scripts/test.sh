#!/usr/bin/env bash
# Runs the VeraFlow unit + UI tests on an available iPhone simulator, or the unit tests
# against the native Mac build.
# Usage: scripts/test.sh [--unit-only | --only <Target[/Class[/test]]> | --platform macos]
#   e.g. scripts/test.sh --only VeraFlowUITests/LibraryManagementTests
#        scripts/test.sh --platform macos      # VeraFlow-macOS scheme, unit tests on this Mac
set -euo pipefail

cd "$(dirname "$0")/.."

UNIT_ONLY=0
ONLY=""
PLATFORM="ios"
if [[ "${1:-}" == "--unit-only" ]]; then UNIT_ONLY=1; fi
if [[ "${1:-}" == "--only" ]]; then ONLY="${2:?--only needs a test target, class or test}"; fi
if [[ "${1:-}" == "--platform" ]]; then PLATFORM="${2:?--platform needs ios or macos}"; fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. This script needs a Mac with Xcode installed." >&2
  exit 1
fi

# Always regenerate the project so it matches the files on disk. project.yml is
# the source of truth; a stale VeraFlow.xcodeproj can reference files that no
# longer exist ("Build input files cannot be found").
if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Regenerating VeraFlow.xcodeproj from project.yml"
  xcodegen generate --quiet
elif [[ ! -d VeraFlow.xcodeproj ]]; then
  echo "error: VeraFlow.xcodeproj not found and xcodegen is not installed." >&2
  echo "       brew install xcodegen && xcodegen generate" >&2
  exit 1
else
  echo "warning: xcodegen not installed; using existing VeraFlow.xcodeproj (may be stale)" >&2
fi

# Pick a simulator: prefer one that's already booted, else the first available iPhone.
pick_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
booted, candidates = [], []
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable", False) or "iPhone" not in d["name"]:
            continue
        (booted if d.get("state") == "Booted" else candidates).append((runtime, d))
def key(item):
    runtime, d = item
    return (runtime, d["name"])
chosen = sorted(booted, key=key) or sorted(candidates, key=key, reverse=True)
if not chosen:
    sys.exit(1)
print(chosen[0][1]["udid"])
'
}

if [[ "$PLATFORM" == "macos" ]]; then
  # The Mac build (v1.1 plan item 15): the same unit tests, no simulator, no UI tests yet.
  echo "==> Testing the Mac build on this Mac"
  set -x
  xcodebuild test \
    -project VeraFlow.xcodeproj \
    -scheme VeraFlow-macOS \
    -destination "platform=macOS" \
    -configuration Debug \
    | { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi; }
  exit "${PIPESTATUS[0]}"
fi

UDID="$(pick_simulator || true)"
if [[ -z "$UDID" ]]; then
  echo "error: no available iPhone simulator. Open Xcode > Settings > Components and install an iOS 26+ simulator." >&2
  exit 1
fi
echo "==> Using simulator $UDID"

# macOS ships bash 3.2, where an empty array trips `set -u`, so build the flag as a string.
ONLY_TESTING=""
if [[ "$UNIT_ONLY" == "1" ]]; then
  ONLY_TESTING="-only-testing:VeraFlowTests"
elif [[ -n "$ONLY" ]]; then
  ONLY_TESTING="-only-testing:$ONLY"
fi

set -x
# shellcheck disable=SC2086  # ONLY_TESTING is intentionally unquoted so an empty value adds no argument
xcodebuild test \
  -project VeraFlow.xcodeproj \
  -scheme VeraFlow \
  -destination "platform=iOS Simulator,id=$UDID" \
  -configuration Debug \
  $ONLY_TESTING \
  | { if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi; }
