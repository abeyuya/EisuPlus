# リリース手順

`v*` タグを push すると Xcode Cloud がビルド → 公証 → GitHub Release へのアップロードまで行う。

```sh
git tag v0.2.0
git push origin v0.2.0
```

- `ci_scripts/ci_post_clone.sh`: xcodegen で xcodeproj を生成。タグからバージョン (`MARKETING_VERSION`)、`CI_BUILD_NUMBER` からビルド番号を設定
- `ci_scripts/ci_post_xcodebuild.sh`: Developer ID 署名済みアプリを notarytool で公証・staple し、`EisuMod-<version>.zip` を GitHub Release にアップロード

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

### 2. ワークフローの作成

1. `xcodegen generate` して `EisuMod.xcodeproj` を Xcode で開く
2. Integrate → Create Workflow… (GitHub 連携と App Store Connect のアプリ登録を求められたら従う)
3. ワークフローを編集
   - Start Conditions: 既定の Branch Changes を削除し、**Tag Changes** を追加 (Custom Tags: `v` で始まるもの)
   - Actions: **Archive** (Platform: macOS, Scheme: EisuMod)
   - Environment → Environment Variables に以下を追加し、すべて **Secret** にチェック

| 名前 | 値 |
|---|---|
| `ASC_KEY_ID` | API キーの Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` の結果 |
| `GITHUB_RELEASE_TOKEN` | fine-grained PAT |

### 注意

- 無料枠は Apple Developer Program 付属の月 25 compute hours
- ビルド失敗時やタグ以外で起動した場合、post_xcodebuild はアップロードせずに終了する
