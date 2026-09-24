#!/bin/zsh
# Mac App Store 用にアーカイブし、.pkg を書き出す。--upload を付けると App Store Connect へアップロードする
set -euo pipefail

cd "$(dirname "$0")/.."

destination=export
[[ "${1:-}" == "--upload" ]] && destination=upload

archive=build-mas/EisuMod.xcarchive
options=build-mas/ExportOptions.plist

xcodegen generate -q
rm -rf "$archive"
xcodebuild -project EisuMod.xcodeproj -scheme EisuMod-AppStore -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -allowProvisioningUpdates -quiet archive

mkdir -p build-mas
cp Config/ExportOptions-AppStore.plist "$options"
plutil -replace destination -string "$destination" "$options"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
    -exportPath build-mas/export -allowProvisioningUpdates

echo "done ($destination): build-mas/export"
