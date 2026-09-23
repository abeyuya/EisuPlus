#!/bin/zsh
# Release ビルドして /Applications/Btry.app に配置し、起動し直す
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate -q
xcodebuild -project Btry.xcodeproj -scheme Btry -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet build

osascript -e 'quit app "Btry"' 2>/dev/null || true
sleep 1
rsync -a --delete build/Build/Products/Release/Btry.app/ /Applications/Btry.app/
open /Applications/Btry.app

echo "installed: /Applications/Btry.app"
