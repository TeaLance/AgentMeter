#!/usr/bin/env bash
# Fail if a Mach-O binary records a different SDK version than the SDK it was
# built against. macOS picks the app's look from the recorded SDK version
# (LC_BUILD_VERSION "sdk"): a binary that claims an old SDK silently loses the
# current system look, e.g. Liquid Glass on macOS 26+.
#
# Usage: Scripts/check-sdk-version.sh <binary>
set -euo pipefail

BIN="${1:?usage: Scripts/check-sdk-version.sh <binary>}"
EXPECTED="$(xcrun --show-sdk-version)"
# One line per distinct recorded version across all architectures.
RECORDED="$(otool -arch all -l "$BIN" | awk '$1 == "sdk" { print $2 }' | sort -u)"

if [ "$RECORDED" != "$EXPECTED" ]; then
    echo "error: $BIN records SDK version(s) [$(echo $RECORDED)], expected $EXPECTED." >&2
    echo "       macOS would treat the app as built with an older SDK and drop the current look." >&2
    exit 1
fi
echo "    SDK version OK ($EXPECTED)"
