#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build"
xcrun swiftc -swift-version 5 "$ROOT"/Shared/*.swift "$ROOT/Mac/MusicBridge.swift" "$ROOT/Tests/ProtocolTests.swift" -o "$ROOT/.build/protocol-tests"
"$ROOT/.build/protocol-tests"
