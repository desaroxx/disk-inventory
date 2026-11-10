#!/bin/bash
# Builds dist/DiskInventory.app (universal), then a DMG and a zip next to it.
#
#   scripts/build-app.sh               # version from VERSION
#   VERSION=1.2.0 scripts/build-app.sh
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… scripts/build-app.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed: it runs, but Gatekeeper asks users to
# confirm it on first launch. With NOTARY_PROFILE (an `xcrun notarytool store-credentials`
# profile) the DMG is notarized and stapled.
set -euo pipefail

cd "$(dirname "$0")/.."
NAME=DiskInventory
VERSION=${VERSION:-$(cat VERSION)}
BUILD=${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
DIST=dist
APP="$DIST/$NAME.app"

echo "==> Building $NAME $VERSION ($BUILD)"
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Credits.html "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing with identity: $SIGN_IDENTITY"
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && SIGN_ARGS+=(--options runtime --timestamp)
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict "$APP"

echo "==> Packaging"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$NAME-$VERSION.dmg"
hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
[[ "$SIGN_IDENTITY" != "-" ]] && codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

ditto -c -k --keepParent "$APP" "$DIST/$NAME-$VERSION.zip"
(cd "$DIST" && shasum -a 256 "$NAME-$VERSION.dmg" "$NAME-$VERSION.zip" > SHA256SUMS.txt)

echo "==> Done"
ls -lh "$DIST"
