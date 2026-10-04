# リリース手順

`v*` タグを push すると Xcode Cloud がビルド → 公証 → GitHub Release へのアップロードまで行う。

```sh
git tag v0.2.0
git push origin v0.2.0
```

- `ci_scripts/ci_post_clone.sh`: xcodegen で xcodeproj を生成。タグからバージョン (`MARKETING_VERSION`)、`CI_BUILD_NUMBER` からビルド番号を設定
- `ci_scripts/ci_post_xcodebuild.sh`: Developer ID 署名済みアプリを notarytool で公証・staple し、`EisuPlus-<version>.zip` を GitHub Release にアップロード

タグ以外 (ブランチ / PR) で起動された Archive も、`build-<ビルド番号>` タグの **prerelease** として `EisuPlus-<version>-build<ビルド番号>.zip` をアップロードする。prerelease は `install-latest.sh` の「最新リリース」には含まれない。

## リリース PR

`main` に push されると GitHub Actions (`.github/workflows/create-release-pr.yml`) が [git-pr-release](https://github.com/x-motemen/git-pr-release) で `main` → `release/production` のリリース PR を作成・更新する。PR 本文には前回リリース以降に `main` へマージされた PR がチェックリストで並ぶ。

初回のみ以下の準備が必要。

- `release/production` ブランチを作成しておく (git-pr-release は存在しないブランチへの PR を作れない)
  ```sh
  git push origin v0.1.0:refs/heads/release/production   # 直近リリースのタグから切る
  ```
- Settings → Actions → General → Workflow permissions で **Allow GitHub Actions to create and approve pull requests** を有効にする

## 他の Mac へのインストール

private リポジトリなので `gh auth login` 済みであること。

```sh
./scripts/install-latest.sh          # 最新リリース
./scripts/install-latest.sh v0.2.0   # バージョン指定
```

## Xcode Cloud の初期設定 (初回のみ)

### 1. API キー / トークンの用意

- App Store Connect → ユーザとアクセス → 統合 → App Store Connect API でキーを発行 (アクセス: Developer)
  - Key ID / Issuer ID / `.p8` ファイルを控える
- GitHub で fine-grained PAT を発行
  - Repository access: `abeyuya/EisuMod` のみ
  - Permissions: Contents → Read and write
- Developer ID Application 証明書を `.p12` で書き出す: `./scripts/export-developer-id-p12.sh` を実行すると、`DEVELOPER_ID_P12_BASE64` と `DEVELOPER_ID_P12_PASSWORD` の値が順にクリップボードに入る (ファイルは残らない)
  - Xcode Cloud は Developer ID 版を書き出さず (Distribution Preparation に Developer ID がない)、API キーでは Developer ID のクラウド署名もできない。そのため `ci_post_xcodebuild.sh` がこの証明書で archive から Developer ID 版を書き出す

### 2. ワークフローの作成

1. `xcodegen generate` して `EisuMod.xcodeproj` を Xcode で開く
2. Integrate → Create Workflow… (GitHub 連携と App Store Connect のアプリ登録を求められたら従う)
3. ワークフローを編集
   - Start Conditions: **Tag Changes** を追加 (Custom Tags: `v` で始まるもの)。ブランチ起動のビルドも prerelease として欲しければ Branch Changes も残す
   - Actions: **Archive** (Platform: macOS, Scheme: EisuMod)
   - Environment → Environment Variables に以下を追加し、すべて **Secret** にチェック

| 名前 | 値 |
|---|---|
| `ASC_KEY_ID` | API キーの Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` の結果 |
| `GITHUB_RELEASE_TOKEN` | fine-grained PAT |
| `DEVELOPER_ID_P12_BASE64` | `scripts/export-developer-id-p12.sh` が 1 つ目にクリップボードへ入れる値 |
| `DEVELOPER_ID_P12_PASSWORD` | 同じく 2 つ目にクリップボードへ入れる値 |

### 注意

- 無料枠は Apple Developer Program 付属の月 25 compute hours
- Archive 以外のアクションやビルド失敗時は、post_xcodebuild はアップロードせずに終了する
