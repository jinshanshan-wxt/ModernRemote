#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/iOS"
xcrun xcodebuild -project "$ROOT/ModernRemote.xcodeproj" -scheme ModernRemoteiOS -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$BUILD" CODE_SIGNING_ALLOWED=NO build
STAGING="$(mktemp -d "$ROOT/.build/ipa.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Payload"
ditto "$BUILD/Build/Products/Release-iphoneos/ModernRemoteiOS.app" "$STAGING/Payload/ModernRemoteiOS.app"
ditto -c -k --keepParent "$STAGING/Payload" "$ROOT/.build/ModernRemote-iOS-unsigned.ipa"
printf 'Unsigned IPA: %s\nRe-sign with your own certificate and profile before installing.\n' "$ROOT/.build/ModernRemote-iOS-unsigned.ipa"
