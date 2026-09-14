#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/ModernRemoteMac.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" "$ROOT"/Shared/*.swift "$ROOT"/Mac/*.swift -o "$APP/Contents/MacOS/ModernRemoteMac"
cp "$ROOT/Config/Mac-Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ModernRemoteMac' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.example.modernremote.mac' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.0' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 1' "$APP/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements "$ROOT/Config/Mac.entitlements" "$APP"
printf 'Built local app: %s\n' "$APP"
