#!/bin/bash
# release/production の HEAD に付ける正式リリースのバージョン (X.Y.Z) を出力する (.github/workflows/tag-release.yml から呼ぶ)
# ubuntu のランナーで動かすので zsh ではなく bash で書く
#
# - 最新の vX.Y.Z の次のパッチ。project.yml の MARKETING_VERSION のほうが大きければそれ (マイナー・メジャーを上げるとき)
# - HEAD にすでに vX.Y.Z が付いていれば何も出力しない (再実行で二重にタグを付けない)
set -euo pipefail

cd "$(dirname "$0")/.."

semver='^v[0-9]+\.[0-9]+\.[0-9]+$'

if [[ -n "$(git tag --points-at HEAD | { grep -E "$semver" || true; })" ]]; then
  exit 0
fi

marketing="$(sed -n -E 's/^ *MARKETING_VERSION: "?([0-9]+\.[0-9]+\.[0-9]+)"?$/\1/p' project.yml | head -n 1)"
if [[ -z "$marketing" ]]; then
  echo "error: project.yml に X.Y.Z 形式の MARKETING_VERSION がない" >&2
  exit 1
fi

latest="$(git tag --list 'v*' | { grep -E "$semver" || true; } | sort -V | tail -n 1)"
if [[ -z "$latest" ]]; then
  echo "$marketing"
  exit 0
fi

IFS=. read -r major minor patch <<< "${latest#v}"
# 10# を付けないと、08 のような 0 始まりが 8 進数として扱われてエラーになる
next="$major.$minor.$((10#$patch + 1))"
if [[ "$(printf '%s\n' "$next" "$marketing" | sort -V | tail -n 1)" == "$marketing" ]]; then
  next="$marketing"
fi
echo "$next"
