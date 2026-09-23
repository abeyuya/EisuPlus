#!/bin/zsh
# Xcode Cloud: Archive 後に Developer ID 署名済みアプリを公証し、GitHub Release にアップロードする
#
# 必要な Secret 環境変数 (Xcode Cloud のワークフローで設定):
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64 : notarytool 用の App Store Connect API キー
#   GITHUB_RELEASE_TOKEN                          : Contents: Read and write 権限の fine-grained PAT
set -euo pipefail

GITHUB_REPO="abeyuya/EisuMod"

if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "archive アクションではないのでスキップ"
  exit 0
fi
if [[ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]]; then
  echo "xcodebuild が失敗しているのでスキップ"
  exit 0
fi
if [[ -z "${CI_TAG:-}" ]]; then
  echo "タグ起動ではないのでスキップ"
  exit 0
fi

# CI_DEVELOPER_ID_SIGNED_APP_PATH は .app そのもの、または .app を含むディレクトリ
signed_path="${CI_DEVELOPER_ID_SIGNED_APP_PATH:?Developer ID 署名済みアプリがない}"
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

work_dir="$(mktemp -d)"
key_path="$work_dir/AuthKey.p8"
echo "$ASC_KEY_P8_BASE64" | base64 --decode > "$key_path"

# 公証
ditto -c -k --keepParent "$app_path" "$work_dir/notarize.zip"
# 失敗時も結果とログを出したいので、ここでは終了コードで止めない
result="$(xcrun notarytool submit "$work_dir/notarize.zip" --wait --output-format json \
  --key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")" || true
echo "$result"
submission_id="$(echo "$result" | plutil -extract id raw - 2>/dev/null)" || submission_id=""
status="$(echo "$result" | plutil -extract status raw - 2>/dev/null)" || status=""
if [[ "$status" != "Accepted" ]]; then
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" \
      --key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" || true
  fi
  echo "error: 公証に失敗: $status" >&2
  exit 1
fi
xcrun stapler staple "$app_path"

asset_name="EisuMod-${CI_TAG#v}.zip"
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
  "https://api.github.com/repos/$GITHUB_REPO/releases/tags/$CI_TAG")"; then
  release_id="$(echo "$release" | plutil -extract id raw -)"
  asset_count="$(echo "$release" | plutil -extract assets raw -)"
  for (( i = 0; i < asset_count; i++ )); do
    if [[ "$(echo "$release" | plutil -extract "assets.$i.name" raw -)" == "$asset_name" ]]; then
      asset_id="$(echo "$release" | plutil -extract "assets.$i.id" raw -)"
      curl -sS --fail-with-body "${api_headers[@]}" -X DELETE \
        "https://api.github.com/repos/$GITHUB_REPO/releases/assets/$asset_id"
    fi
  done
else
  release="$(curl -sS --fail-with-body "${api_headers[@]}" \
    -X POST "https://api.github.com/repos/$GITHUB_REPO/releases" \
    -d "{\"tag_name\":\"$CI_TAG\",\"name\":\"$CI_TAG\",\"generate_release_notes\":true}")"
  release_id="$(echo "$release" | plutil -extract id raw -)"
fi

curl -sS --fail-with-body "${api_headers[@]}" \
  -H "Content-Type: application/zip" \
  -X POST "https://uploads.github.com/repos/$GITHUB_REPO/releases/$release_id/assets?name=$asset_name" \
  --data-binary "@$asset_path" > /dev/null

echo "uploaded: $asset_name -> release $CI_TAG"
