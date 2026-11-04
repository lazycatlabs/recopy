#!/bin/zsh
# Builds ReCopy in Release and packages it for a GitHub release and the Homebrew cask:
#   build/ReCopy-<version>.dmg   drag-to-Applications disk image
#   build/ReCopy-<version>.zip   the same app, for `brew install --cask`
#
#   scripts/make_release.sh
#   ADHOC_SIGN=1 scripts/make_release.sh   (CI: no certificate, signed ad hoc)
#
# The app is signed with the "Apple Development" identity of the project's DEVELOPMENT_TEAM (set SIGN_IDENTITY to use
# another), so macOS keeps the Accessibility permission across updates. It stops if the keychain has none.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
BUILD="$ROOT/build"
DERIVED="$BUILD/DerivedData"
APP="$DERIVED/Build/Products/Release/ReCopy.app"

# ADHOC_SIGN=1 builds and signs ad hoc, without the project's team, e.g. on CI without a certificate.
SIGNING=()
[[ "${ADHOC_SIGN:-}" == 1 ]] && SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)

echo "→ Building ReCopy (Release)…"
xcodebuild -project ReCopy.xcodeproj -scheme ReCopy -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" "${SIGNING[@]}" -quiet build
[[ -d "$APP" ]] || { echo "✗ Build finished but $APP is missing" >&2; exit 1; }

# The keychain's Apple Development identity whose certificate belongs to team $1.
team_identity() {
  security find-identity -v -p codesigning | awk -F'"' '/"Apple Development/ {print $2}' | while read -r name; do
    if security find-certificate -c "$name" -p | openssl x509 -noout -subject | grep -q "OU *= *$1"; then
      print -r -- "$name"
      return
    fi
  done
}

IDENTITY=""
if [[ "${ADHOC_SIGN:-}" != 1 ]]; then
  TEAM=$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' ReCopy.xcodeproj/project.pbxproj | awk '{print $3}')
  IDENTITY=${SIGN_IDENTITY:-$(team_identity "$TEAM")}
  [[ -n "$IDENTITY" ]] || { echo "✗ No Apple Development identity for team $TEAM in the keychain (or set SIGN_IDENTITY)" >&2; exit 1; }
fi
echo "→ Signing with ${IDENTITY:-ad hoc}…"
codesign --force --deep --options runtime --timestamp=none --sign "${IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/ReCopy-$VERSION.dmg"
ZIP="$BUILD/ReCopy-$VERSION.zip"

echo "→ Packaging ReCopy $VERSION…"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/ReCopy.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG" "$ZIP"
hdiutil create -volname "ReCopy $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet
ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
echo "  sha256 (for the cask): $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
