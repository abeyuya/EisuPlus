#!/bin/zsh
# GitHub Release の最新版をダウンロードして /Applications/EisuPlus.app に配置し、起動し直す
# 事前に `gh auth login` が必要 (private リポジトリのため)
set -euo pipefail

repo="abeyuya/EisuMod"
tag="${1:-}"  # 省略時は最新リリース

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# 古いリリースの asset は EisuMod-*.zip、新しいものは EisuPlus-*.zip
gh release download ${tag:+"$tag"} --repo "$repo" --pattern 'Eisu*.zip' --dir "$work_dir"
ditto -x -k "$work_dir"/Eisu*.zip "$work_dir"
app_path=("$work_dir"/Eisu*.app)

# 旧名 (EisuMod.app) で動いているものも止めるため、バンドル ID で終了させる
osascript -e 'quit app id "com.github.abeyuya.EisuMod"' 2>/dev/null || true
sleep 1
# 旧名の .app が残っているとバンドル ID が重複するので消す
rm -rf /Applications/EisuMod.app
rsync -a --delete "${app_path[1]}/" /Applications/EisuPlus.app/
open /Applications/EisuPlus.app

echo "installed: /Applications/EisuPlus.app ($(defaults read /Applications/EisuPlus.app/Contents/Info.plist CFBundleShortVersionString))"
