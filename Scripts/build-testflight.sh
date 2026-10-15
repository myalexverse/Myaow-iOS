#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun swift Scripts/PrepareStoreIcons.swift

# Builds locally; uploading and inviting testers are separate actions.
build_number=${1:?Usage: bash Scripts/build-testflight.sh 2610.4.1}
if [[ ! "$build_number" =~ ^[1-9][0-9]{0,3}\.[0-9]{1,2}\.[0-9]{1,2}$ ]]; then
  echo "Use a numeric build number such as 2610.4.1" >&2
  exit 2
fi
output_dir=${MYAOW_TESTFLIGHT_OUTPUT:-$PWD/Builds/TestFlight}
archive_path="$output_dir/Myaow-1.0-$build_number.xcarchive"
mkdir -p "$output_dir"
if [[ -e "$archive_path" ]]; then
  echo "Archive already exists; choose a new build number." >&2
  exit 2
fi
xcodebuild -project Myaow.xcodeproj -scheme Myaow -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/myaow-testflight-derived \
  -archivePath "$archive_path" -disableAutomaticPackageResolution \
  CURRENT_PROJECT_VERSION="$build_number" archive
python3 Scripts/validate-testflight-archive.py "$archive_path"
echo "Archive prepared: $archive_path"
