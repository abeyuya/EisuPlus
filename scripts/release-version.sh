#!/bin/bash
# project.yml の MARKETING_VERSION (X.Y.Z) が、リリースするバージョンとして正しいかを確かめて出力する
# (.github/workflows/check-release-version.yml と tag-release.yml から呼ぶ。ubuntu のランナーで動かすので bash で書く)
#
# - MARKETING_VERSION が最新のリリース (vX.Y.Z のタグ) より大きければ、それを出力する
# - 大きくなければエラーで終わる。リリース PR をマージする前に MARKETING_VERSION を上げておく
# - HEAD にすでに vMARKETING_VERSION が付いていれば何も出力しない (再実行で二重にタグを付けない)
set -euo pipefail

cd "$(dirname "$0")/.."

error() {
  echo "${GITHUB_ACTIONS:+::error::}$*" >&2
  exit 1
}

version="$(sed -n -E 's/^ *MARKETING_VERSION: "?([0-9]+\.[0-9]+\.[0-9]+)"?$/\1/p' project.yml | head -n 1)"
[[ -n "$version" ]] || error "project.yml に X.Y.Z 形式の MARKETING_VERSION がない"

if [[ -n "$(git tag --points-at HEAD | { grep -Fx "v$version" || true; })" ]]; then
  exit 0
fi

latest="$(git tag --list 'v*' | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"
if [[ -n "$latest" ]]; then
  greatest="$(printf '%s\n' "${latest#v}" "$version" | sort -V | tail -n 1)"
  if [[ "v$version" == "$latest" || "$greatest" != "$version" ]]; then
    error "MARKETING_VERSION ($version) が最新のリリース ($latest) より大きくない。project.yml の MARKETING_VERSION を上げる"
  fi
fi
echo "$version"
