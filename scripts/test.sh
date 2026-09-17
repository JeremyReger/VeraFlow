#!/usr/bin/env bash
# Runs the VeraFlow unit + UI tests on an available iPhone simulator.
# Usage: scripts/test.sh [--unit-only]
set -euo pipefail

cd "$(dirname "$0")/.."

UNIT_ONLY=0
if [[ "${1:-}" == "--unit-only" ]]; then UNIT_ONLY=1; fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found. This script needs a Mac with Xcode installed." >&2
  exit 1
fi

if [[ ! -d VeraFlow.xcodeproj ]]; then
  if command -v xcodegen >/dev/null 2>&1; then
    echo "==> VeraFlow.xcodeproj not found; generating with xcodegen"
    xcodegen generate
  else
    echo "error: VeraFlow.xcodeproj not found and xcodegen is not installed." >&2
    echo "       brew install xcodegen && xcodegen generate" >&2
    exit 1
  fi
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
