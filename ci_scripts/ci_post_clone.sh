#!/bin/zsh
# Xcode Cloud: clone 直後に xcodeproj を生成する (xcodeproj は gitignore している)
set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

brew install xcodegen

# タグ (v1.2.3) から起動された場合はバージョンをタグに合わせる
if [[ -n "${CI_TAG:-}" ]]; then
  version="${CI_TAG#v}"
  sed -i '' -E "s/^( *MARKETING_VERSION: ).*/\1\"${version}\"/" project.yml
fi
if [[ -n "${CI_BUILD_NUMBER:-}" ]]; then
  sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: ).*/\1\"${CI_BUILD_NUMBER}\"/" project.yml
fi

xcodegen generate
