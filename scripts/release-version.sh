#!/bin/bash
# project.yml の MARKETING_VERSION (X.Y.Z) が、リリースするバージョンとして正しいかを確かめて出力する
# (.github/workflows/check-release-version.yml と tag-release.yml から呼ぶ。ubuntu のランナーで動かすので bash で書く)
#
# - MARKETING_VERSION が最新のリリース (vX.Y.Z のタグ) より大きければ、それを出力する
# - 大きくなければエラーで終わる。リリース PR をマージする前に MARKETING_VERSION を上げておく
set -euo pipefail

cd "$(dirname "$0")/.."

error() {
  echo "${GITHUB_ACTIONS:+::error::}$*" >&2
  exit 1
}

# 最初の一致で sed を終わらせる (head に渡すと pipefail の下で SIGPIPE を拾いうる)
version="$(sed -n -E '/^ *MARKETING_VERSION: "?([0-9]+\.[0-9]+\.[0-9]+)"?$/{s//\1/p;q;}' project.yml)"
[[ -n "$version" ]] || error "project.yml に X.Y.Z 形式の MARKETING_VERSION がない"

latest="$(git tag --list 'v*' | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"
if [[ -n "$latest" ]]; then
  greatest="$(printf '%s\n' "${latest#v}" "$version" | sort -V | tail -n 1)"
  if [[ "v$version" == "$latest" || "$greatest" != "$version" ]]; then
    error "MARKETING_VERSION ($version) が最新のリリース ($latest) より大きくない。project.yml の MARKETING_VERSION を上げる"
  fi
fi
echo "$version"
