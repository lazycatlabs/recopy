#!/bin/zsh
# Builds ReCopy in Release and packages it for a GitHub release and the Homebrew cask:
#   build/ReCopy-<version>.dmg   drag-to-Applications disk image
#   build/ReCopy-<version>.zip   the same app, for `brew install --cask`
#
#   scripts/make_release.sh
#   ADHOC_SIGN=1 scripts/make_release.sh   (CI: no certificate, signed ad hoc, not notarized)
#
# The app and DMG are signed with the project team's "Developer ID Application" identity (set SIGN_IDENTITY to use
# another), then notarized and stapled, so Gatekeeper opens them on any Mac.
#
# One-time setup:
#   - a "Developer ID Application" certificate for the team in the keychain
#   - notary credentials: xcrun notarytool store-credentials notary --apple-id <apple-id> --team-id 53KYGKG9B9
# NOTARY_PROFILE overrides the keychain profile name (default: notary).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
APP="$DERIVED/Build/Products/Release/ReCopy.app"
ADHOC=${ADHOC_SIGN:-}
PROFILE=${NOTARY_PROFILE:-notary}

# ADHOC_SIGN=1 builds and signs ad hoc, without the project's team, e.g. on CI without a certificate.
SIGNING=()
[[ "$ADHOC" == 1 ]] && SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)

IDENTITY=""
if [[ "$ADHOC" != 1 ]]; then
  TEAM=$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' ReCopy.xcodeproj/project.pbxproj | awk '{print $3}')
  IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application:.*($TEAM)" | awk '{print $2}' || true)}
  [[ -n "$IDENTITY" ]] || { echo "✗ No Developer ID Application identity for team $TEAM in the keychain (or set SIGN_IDENTITY)" >&2; exit 1; }
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null ||
    { echo "✗ No notary credentials in keychain profile \"$PROFILE\" (see the setup at the top of this script)" >&2; exit 1; }
fi

echo "→ Building ReCopy (Release)…"
xcodebuild -project ReCopy.xcodeproj -scheme ReCopy -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" "${SIGNING[@]}" -quiet build
[[ -d "$APP" ]] || { echo "✗ Build finished but $APP is missing" >&2; exit 1; }

# Notarization needs the hardened runtime and a secure timestamp.
echo "→ Signing with ${IDENTITY:-ad hoc}…"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --deep --options runtime --timestamp=none --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# Sends $2 (a zip of the app, or the DMG itself) to Apple's notary service, then staples the ticket to $1.
notarize() {
  echo "→ Notarizing $(basename "$1")…"
  local result
  result=$(xcrun notarytool submit "$2" --keychain-profile "$PROFILE" --wait) || true
  print -r -- "$result"
  [[ "$result" == *"status: Accepted"* ]] ||
    { echo "✗ Notarization of $(basename "$1") failed (xcrun notarytool log <id> --keychain-profile $PROFILE)" >&2; exit 1; }
  xcrun stapler staple "$1"
}

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/ReCopy-$VERSION.dmg"
ZIP="$BUILD/ReCopy-$VERSION.zip"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Notarize the app itself and staple it, so the zip works offline too.
if [[ -n "$IDENTITY" ]]; then
  ditto -c -k --keepParent "$APP" "$STAGING/notarize.zip"
  notarize "$APP" "$STAGING/notarize.zip"
  rm "$STAGING/notarize.zip"
fi

echo "→ Packaging ReCopy $VERSION…"
ditto "$APP" "$STAGING/ReCopy.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG" "$ZIP"
hdiutil create -volname "ReCopy $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -n "$IDENTITY" ]]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  notarize "$DMG" "$DMG"
  spctl --assess --type execute -v "$APP"
  xcrun stapler validate "$DMG"
fi

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "  sha256 (for the cask): $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
