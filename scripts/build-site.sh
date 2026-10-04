#!/bin/zsh
# GitHub Pages に置くサイトを組み立てる (.github/workflows/pages.yml から呼ぶ)
# site/ をコピーしてダウンロードリンクを最新リリースに向け、Sparkle の appcast.xml を書き出す
#
# 使い方: scripts/build-site.sh <出力ディレクトリ>
# 必要な環境変数:
#   GH_TOKEN            : リリースを読める GitHub のトークン
#   SPARKLE_PRIVATE_KEY : Sparkle の EdDSA 秘密鍵 (`generate_keys -x` で書き出したもの)
#   SPARKLE_BIN         : Sparkle の配布物の bin ディレクトリ (sign_update がある場所)
set -euo pipefail

repo="${GITHUB_REPOSITORY:-abeyuya/EisuMod}"
site_url="https://abeyuya.github.io/EisuMod"
out="${1:?出力ディレクトリを指定する}"
root="${0:A:h:h}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

rm -rf "$out"
mkdir -p "$out"
cp -R "$root/site/." "$out/"

# 正式リリース (prerelease と draft を除く) のうち、バージョンが最大のもの。
# GitHub の latest はタグのコミット日時で決まるので、旧系統の hotfix (v0.2.0 の後の v0.1.1 など) を選んでしまう。
# Sparkle はビルド番号で新旧を比べるので、それを appcast に載せると新しい系統の利用者にダウングレードが配られる
tags="$(gh api "repos/$repo/releases" --paginate --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name')"
tag="$(print -r -- "$tags" | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true; } | sort -V | tail -n 1)"
if [[ -n "$tag" ]]; then
  # リリースノートを HTML で受け取る
  release="$(gh api "repos/$repo/releases/tags/$tag" -H "Accept: application/vnd.github.html+json")"
  gh release download "$tag" --repo "$repo" --pattern 'EisuPlus-*.zip' --dir "$work_dir"
  zips=("$work_dir"/EisuPlus-*.zip(N))
  if (( ${#zips} != 1 )); then
    echo "error: $tag に EisuPlus-*.zip が1つだけあるはずが ${#zips} 個ある" >&2
    exit 1
  fi
  zip_path="${zips[1]}"
  asset_name="${zip_path:t}"
  download_url="https://github.com/$repo/releases/download/$tag/$asset_name"
  release_url="https://github.com/$repo/releases/tag/$tag"

  ditto -x -k "$zip_path" "$work_dir/app"
  info_plist=("$work_dir"/app/*.app/Contents/Info.plist)
  version="$(plutil -extract CFBundleShortVersionString raw "${info_plist[1]}")"
  build_number="$(plutil -extract CFBundleVersion raw "${info_plist[1]}")"
  minimum_system_version="$(plutil -extract LSMinimumSystemVersion raw "${info_plist[1]}")"

  # `sparkle:edSignature="..." length="..."` が出力される
  signature="$(print -r -- "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY がない}" \
    | "${SPARKLE_BIN:?SPARKLE_BIN がない}/sign_update" --ed-key-file - "$zip_path")"

  published_at="$(print -r -- "$release" | plutil -extract published_at raw -)"
  pub_date="$(LC_ALL=C date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$published_at" "+%a, %d %b %Y %H:%M:%S +0000")"
  # リリースノートは CDATA に入れるので、終端の `]]>` だけ分割しておく
  notes_html="$(print -r -- "$release" | plutil -extract body_html raw - 2>/dev/null || true)"
  notes_html="${notes_html//]]>/]]]]><![CDATA[>}"

  item="
    <item>
      <title>$version</title>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$build_number</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system_version</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$release_url</sparkle:fullReleaseNotesLink>
      <description><![CDATA[$notes_html]]></description>
      <enclosure url=\"$download_url\" $signature type=\"application/octet-stream\"/>
    </item>"
  version_label="バージョン $version"
  echo "latest release: $tag ($version build $build_number)"
else
  # 正式リリースがまだなければ、ダウンロードボタンはリリース一覧に向け、appcast は空にする
  echo "warning: 正式リリースがないので appcast.xml は空にする" >&2
  version_label="近日公開"
  minimum_system_version="15.0"
  download_url="https://github.com/$repo/releases"
  item=""
fi

# Sparkle は新しいバージョンがあるかどうかだけを見るので、最新の1件だけを載せる
cat > "$out/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>EisuPlus</title>
    <link>$site_url/</link>
    <language>ja</language>$item
  </channel>
</rss>
EOF
xmllint --noout "$out/appcast.xml"

for page in "$out"/*.html; do
  sed -i '' \
    -e "s|{{VERSION_LABEL}}|$version_label|g" \
    -e "s|{{DOWNLOAD_URL}}|$download_url|g" \
    -e "s|{{MINIMUM_SYSTEM_VERSION}}|$minimum_system_version|g" \
    "$page"
done

echo "built: $out"
