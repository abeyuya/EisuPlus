#!/bin/zsh
# Xcode Cloud: Archive 後に Developer ID 署名済みアプリを公証し、GitHub Release にアップロードする
#
# 必要な Secret 環境変数 (Xcode Cloud のワークフローで設定):
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64 : notarytool 用の App Store Connect API キー
#   GITHUB_RELEASE_TOKEN                          : Contents: Read and write 権限の fine-grained PAT
set -euo pipefail

GITHUB_REPO="abeyuya/EisuPlus"

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "archive アクションではないのでスキップ"
  exit 0
fi
if [[ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]]; then
  echo "xcodebuild が失敗しているのでスキップ"
  exit 0
fi

work_dir="$(mktemp -d)"
key_path="$work_dir/AuthKey.p8"
print -r -- "$ASC_KEY_P8_BASE64" | base64 --decode > "$key_path"

# Xcode Cloud の Archive の Distribution Preparation には Developer ID がなく、Developer ID 版は書き出されない。
# API キーでは Developer ID のクラウド署名もできないので、Secret で渡した Developer ID 証明書で archive から書き出す
signed_path="${CI_DEVELOPER_ID_SIGNED_APP_PATH:-}"
if [[ -z "$signed_path" ]]; then
  echo "CI_DEVELOPER_ID_SIGNED_APP_PATH がないので archive から Developer ID で書き出す"
  keychain="$work_dir/signing.keychain-db"
  keychain_password="$(uuidgen)"
  security create-keychain -p "$keychain_password" "$keychain"
  trap 'security delete-keychain "$keychain" 2>/dev/null || true' EXIT
  security set-keychain-settings -lut 3600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  print -r -- "${DEVELOPER_ID_P12_BASE64:?DEVELOPER_ID_P12_BASE64 がない}" | base64 --decode > "$work_dir/developer-id.p12"
  security import "$work_dir/developer-id.p12" -k "$keychain" -P "${DEVELOPER_ID_P12_PASSWORD:?DEVELOPER_ID_P12_PASSWORD がない}" \
    -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" > /dev/null
  # 既存の検索リストの先頭に一時 keychain を足す
  security list-keychains -d user -s "$keychain" ${(f)"$(security list-keychains -d user | tr -d '" ')"}

  signed_path="$work_dir/developer-id"
  xcodebuild -exportArchive -archivePath "${CI_ARCHIVE_PATH:?CI_ARCHIVE_PATH がない}" \
    -exportOptionsPlist "$CI_PRIMARY_REPOSITORY_PATH/Config/ExportOptions-DeveloperID.plist" \
    -exportPath "$signed_path"
fi
# signed_path は .app そのもの、または .app を含むディレクトリ
if [[ "$signed_path" == *.app ]]; then
  app_path="$signed_path"
else
  app_path="$(find "$signed_path" -maxdepth 2 -name '*.app' -type d | head -n 1)"
fi
if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "error: .app が見つからない: $signed_path" >&2
  exit 1
fi
echo "app: $app_path"

# 公証
ditto -c -k --keepParent "$app_path" "$work_dir/notarize.zip"
# 失敗時も結果とログを出したいので、ここでは終了コードで止めない
result="$(xcrun notarytool submit "$work_dir/notarize.zip" --wait --output-format json \
  --key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")" || true
print -r -- "$result"
submission_id="$(print -r -- "$result" | plutil -extract id raw - 2>/dev/null)" || submission_id=""
notarize_status="$(print -r -- "$result" | plutil -extract status raw - 2>/dev/null)" || notarize_status=""
if [[ "$notarize_status" != "Accepted" ]]; then
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" \
      --key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
  fi
  echo "error: 公証に失敗: $notarize_status" >&2
  exit 1
fi
xcrun stapler staple "$app_path"

# タグ起動なら正式リリース、それ以外 (ブランチ / PR 起動) はビルド番号付きの prerelease にする
# prerelease のタグは `v` で始めない (Tag Changes の起動条件に引っかかって再ビルドされるのを防ぐ)
if [[ -n "${CI_TAG:-}" ]]; then
  release_tag="$CI_TAG"
  release_name="$CI_TAG"
  prerelease=false
  asset_name="EisuPlus-${CI_TAG#v}.zip"
else
  version="$(defaults read "$app_path/Contents/Info.plist" CFBundleShortVersionString)"
  build_number="${CI_BUILD_NUMBER:?CI_BUILD_NUMBER がない}"
  source_ref="${CI_BRANCH:-${CI_PULL_REQUEST_SOURCE_BRANCH:-unknown}}"
  source_ref="${source_ref//[\"\\]/}"  # JSON に埋め込むので " と \ を除く
  release_tag="build-$build_number"
  release_name="$version build $build_number ($source_ref)"
  prerelease=true
  asset_name="EisuPlus-$version-build$build_number.zip"
fi
asset_path="$work_dir/$asset_name"
ditto -c -k --keepParent "$app_path" "$asset_path"

# GitHub Release を作成してアップロード
api_headers=(
  -H "Authorization: Bearer $GITHUB_RELEASE_TOKEN"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)
# Rebuild 時などに備え、同じタグの Release があれば再利用し、同名の asset は置き換える
if release="$(curl -sS --fail "${api_headers[@]}" \
  "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$release_tag")"; then
  release_id="$(print -r -- "$release" | plutil -extract id raw -)"
  asset_count="$(print -r -- "$release" | plutil -extract assets raw -)"
  for (( i = 0; i < asset_count; i++ )); do
    if [[ "$(print -r -- "$release" | plutil -extract "assets.$i.name" raw -)" == "$asset_name" ]]; then
      asset_id="$(print -r -- "$release" | plutil -extract "assets.$i.id" raw -)"
      curl -sS --fail-with-body "${api_headers[@]}" -X DELETE \
        "https://api.github.com/repos/$GITHUB_REPO/releases/assets/$asset_id"
    fi
  done
else
  # タグが未作成 (prerelease) の場合は target_commitish のコミットにタグが作られる
  body="{\"tag_name\":\"$release_tag\",\"name\":\"$release_name\",\"target_commitish\":\"${CI_COMMIT:?CI_COMMIT がない}\",\"prerelease\":$prerelease,\"generate_release_notes\":true}"
  release="$(curl -sS --fail-with-body "${api_headers[@]}" \
    -X POST "https://api.github.com/repos/$GITHUB_REPO/releases" -d "$body")"
  release_id="$(print -r -- "$release" | plutil -extract id raw -)"
fi

curl -sS --fail-with-body "${api_headers[@]}" \
  -H "Content-Type: application/zip" \
  -X POST "https://uploads.github.com/repos/$GITHUB_REPO/releases/$release_id/assets?name=$asset_name" \
  --data-binary "@$asset_path" > /dev/null

echo "uploaded: $asset_name -> release $release_tag"

# 正式リリースなら、サイトのダウンロードリンクと Sparkle の appcast.xml を更新する (.github/workflows/pages.yml)
# zip はもう公開できているので、失敗してもビルドは止めない (Actions から手動で再実行できる)
if [[ "$prerelease" == false ]]; then
  curl -sS --fail-with-body "${api_headers[@]}" \
    -X POST "https://api.github.com/repos/$GITHUB_REPO/dispatches" \
    -d '{"event_type":"release-uploaded"}' \
    || echo "warning: サイトの更新を起動できなかった。Actions の Deploy site を手動で実行する" >&2
fi
