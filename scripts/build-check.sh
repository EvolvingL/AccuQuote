#!/bin/bash
# Compiles both AccuQuoteScan and AccuScan for the iOS Simulator without
# code signing — the fastest real test that both apps actually build, no
# device/provisioning needed. Doesn't run RoomPlan/ARKit code (Simulator has
# no camera/LiDAR), but it exercises the full Swift compiler: type errors,
# actor-isolation mistakes, missing symbols, wrong signatures — everything
# that a .pbxproj/brace-balance check can't catch.
#
# Usage: ./scripts/build-check.sh
# Exit code 0 = both apps build clean. Non-zero = at least one failed;
# scroll up for the first "error:" line, which is always the real cause —
# everything after it is usually cascading noise from the same root issue.

set -uo pipefail

ACCUQUOTESCAN_DIR="/Users/lukeashton/PycharmProjects/AccuQuote/iOS/AccuQuoteScan"
ACCUSCAN_DIR="/Users/lukeashton/PycharmProjects/AccuScan-app"

FAILED=0

build_one() {
    local name="$1" dir="$2" project="$3" scheme="$4"
    echo "── Building $name ──────────────────────────────────────"
    if (cd "$dir" && xcodebuild build \
        -project "$project" -scheme "$scheme" \
        -destination "generic/platform=iOS Simulator" -sdk iphonesimulator \
        CODE_SIGNING_ALLOWED=NO 2>&1 | tee "/tmp/build-check-$name.log" | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"); then
        if grep -q "BUILD SUCCEEDED" "/tmp/build-check-$name.log"; then
            echo "✅ $name: BUILD SUCCEEDED"
        else
            echo "❌ $name: BUILD FAILED — full log at /tmp/build-check-$name.log"
            FAILED=1
        fi
    else
        echo "❌ $name: xcodebuild invocation itself failed — full log at /tmp/build-check-$name.log"
        FAILED=1
    fi
    echo
}

build_one "AccuQuoteScan" "$ACCUQUOTESCAN_DIR" "AccuQuoteScan.xcodeproj" "AccuQuoteScan"
build_one "AccuScan"      "$ACCUSCAN_DIR"      "AccuScan.xcodeproj"      "AccuScan"

if [ "$FAILED" -eq 0 ]; then
    echo "Both apps build clean."
else
    echo "At least one app failed to build — see logs above."
fi
exit $FAILED
