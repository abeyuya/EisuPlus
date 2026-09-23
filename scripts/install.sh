#!/bin/zsh
# Release ビルドして /Applications/EisuMod.app に配置し、起動し直す
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate -q
xcodebuild -project EisuMod.xcodeproj -scheme EisuMod -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  build

osascript -e 'quit app "EisuMod"' 2>/dev/null || true
sleep 1
rsync -a --delete build/Build/Products/Release/EisuMod.app/ /Applications/EisuMod.app/
open /Applications/EisuMod.app

echo "installed: /Applications/EisuMod.app"
