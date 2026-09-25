#!/bin/zsh
# Release ビルドして /Applications/EisuPlus.app に配置し、起動し直す
set -euo pipefail

cd "$(dirname "$0")/.."

xcodegen generate -q
xcodebuild -project EisuMod.xcodeproj -scheme EisuMod -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
  build

# 旧名 (EisuMod.app) で動いているものも止めるため、バンドル ID で終了させる
osascript -e 'quit app id "com.github.abeyuya.EisuMod"' 2>/dev/null || true
sleep 1
# 旧名の .app が残っているとバンドル ID が重複するので消す
rm -rf /Applications/EisuMod.app
rsync -a --delete build/Build/Products/Release/EisuPlus.app/ /Applications/EisuPlus.app/
open /Applications/EisuPlus.app

echo "installed: /Applications/EisuPlus.app"
