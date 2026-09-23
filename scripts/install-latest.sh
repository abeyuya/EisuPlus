#!/bin/zsh
# GitHub Release の最新版をダウンロードして /Applications/EisuMod.app に配置し、起動し直す
# 事前に `gh auth login` が必要 (private リポジトリのため)
set -euo pipefail

repo="abeyuya/EisuMod"
tag="${1:-}"  # 省略時は最新リリース

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

gh release download ${tag:+"$tag"} --repo "$repo" --pattern 'EisuMod-*.zip' --dir "$work_dir"
ditto -x -k "$work_dir"/EisuMod-*.zip "$work_dir"

osascript -e 'quit app "EisuMod"' 2>/dev/null || true
sleep 1
rsync -a --delete "$work_dir/EisuMod.app/" /Applications/EisuMod.app/
open /Applications/EisuMod.app

echo "installed: /Applications/EisuMod.app ($(defaults read /Applications/EisuMod.app/Contents/Info.plist CFBundleShortVersionString))"
