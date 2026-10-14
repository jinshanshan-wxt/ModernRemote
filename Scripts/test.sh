#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
xcrun swiftc -swift-version 5 "$ROOT"/Shared/*.swift "$ROOT/Mac/MusicBridge.swift" "$ROOT/Tests/ProtocolTests.swift" -o "$ROOT/.build/protocol-tests"
"$ROOT/.build/protocol-tests"

xcrun swiftc -swift-version 5 "$ROOT"/Shared/*.swift "$ROOT/iOS/RemoteClient.swift" "$ROOT/Tests/PlaybackPresentationTests.swift" -o "$ROOT/.build/playback-presentation-tests"
"$ROOT/.build/playback-presentation-tests"

# Playback must never mutate Music playlist containers or memberships.
if rg -n "make new user playlist|duplicate .* to|delete .*playlist|delete p" "$ROOT/Mac"; then
    printf "FAIL: playlist mutation found in companion source\n" >&2
    exit 1
fi
