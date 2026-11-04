#!/bin/zsh
# Makes the App Store screenshots in fastlane/screenshots/ (English; the App Store shows them for every language) from the E2E tests' sample vault.
# Runs only the E2E tests that take them (about 1 minute; leave the Mac alone), then frames each window.
#
#   scripts/appstore_screenshots.sh
set -euo pipefail

cd "$(dirname "$0")/.."
T=ReCopyUITests/ReCopyE2ETests
scripts/e2e.sh \
  -only-testing:$T/test01PanelHasNewLookAndAnyDayFilter \
  -only-testing:$T/test11GroupsFilterAndAssign \
  -only-testing:$T/test16NotesAreSavedAndSearchable \
  -only-testing:$T/test19AnnotateShapesSizeAndBlur \
  -only-testing:$T/test20hPasteSpecialFormatsCopiedJSON

# Render into a staging folder, so a failed run leaves the current screenshots alone.
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
swift scripts/appstore_screenshots.swift e2e-output/screenshots "$STAGING"
rm -rf fastlane/screenshots/en-US
mv "$STAGING/en-US" fastlane/screenshots/en-US
