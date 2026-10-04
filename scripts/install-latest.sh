#!/bin/zsh
# GitHub Release の最新版をダウンロードして /Applications/EisuPlus.app に配置し、起動し直す
# 事前に `gh auth login` が必要 (private リポジトリのため)
set -euo pipefail

repo="abeyuya/EisuPlus"
tag="${1:-}"  # 省略時は最新リリース

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# 古いリリースの asset は EisuMod-*.zip、新しいものは EisuPlus-*.zip
gh release download ${tag:+"$tag"} --repo "$repo" --pattern 'Eisu*.zip' --dir "$work_dir"
# 改名前に作ったリリースを改名後に再ビルドすると両方の asset が残るので、新しい名前を優先する
zips=("$work_dir"/EisuPlus-*.zip(N) "$work_dir"/EisuMod-*.zip(N))
ditto -x -k "${zips[1]}" "$work_dir/app"
app_path=("$work_dir"/app/*.app)

# 旧名 (EisuMod.app) で動いているものも止めるため、バンドル ID で終了させる
osascript -e 'quit app id "com.github.abeyuya.EisuMod"' 2>/dev/null || true
sleep 1
# 旧名の .app が残っているとバンドル ID が重複するので消す
rm -rf /Applications/EisuMod.app
rsync -a --delete "${app_path[1]}/" /Applications/EisuPlus.app/
open /Applications/EisuPlus.app

echo "installed: /Applications/EisuPlus.app ($(defaults read /Applications/EisuPlus.app/Contents/Info.plist CFBundleShortVersionString))"
