# リリース手順

リリースするバージョンは常に `project.yml` の `MARKETING_VERSION`。

1. `MARKETING_VERSION` を最新のリリース (`vX.Y.Z` のタグ) より大きくして `main` にマージする
2. リリース PR (`main` → `release/production`、[下記](#リリース-pr)) のチェック **Check release version** が通っていることを確かめ、マージする
   - `MARKETING_VERSION` が最新のリリースより大きくなければ、このチェックが落ちる (`scripts/release-version.sh`)
3. `release/production` への push で、GitHub Actions (`.github/workflows/tag-release.yml`) が `v<MARKETING_VERSION>` のタグを付ける
   - 上げ忘れたままマージした場合は、ここでも失敗してタグを付けない。`MARKETING_VERSION` を上げてもう一度リリース PR をマージする
   - コミットにすでにそのタグが付いていれば何もしない
4. 同じ push で Xcode Cloud が `release/production` をビルド → 公証 → `v<MARKETING_VERSION>` の正式リリース (latest) として GitHub Release へアップロードまで行う
   - アップロードの直前に、`v<MARKETING_VERSION>` のタグがビルドしたコミットに付いているかを確かめる。付いていなければ (上げ忘れ、Tag a release の失敗や遅れ) 正式リリースにせず、下記の prerelease にする。タグが付いてから Xcode Cloud で Rebuild すれば正式リリースになる

旧系統への hotfix (`v0.2.0` の後の `v0.1.1` など) はこの手順では出せない (`MARKETING_VERSION` が最新のリリースより大きくないので落ちる)。Sparkle で利用者は最新の系統に上がるので、修正は `MARKETING_VERSION` を上げて最新の系統で出す。

- `ci_scripts/ci_post_clone.sh`: xcodegen で xcodeproj を生成。タグからバージョン (`MARKETING_VERSION`)、`CI_BUILD_NUMBER` からビルド番号を設定
  - Xcode Cloud はパッケージを自動解決しないので、Swift パッケージのバージョンはルートの `Package.resolved` で固定している。`xcodegen generate` のたびに xcodeproj へコピーされる (`project.yml` の `postGenCommand`)
- `ci_scripts/ci_post_xcodebuild.sh`: Developer ID 署名済みアプリを notarytool で公証・staple し、`EisuPlus-<version>.zip` を GitHub Release にアップロード。正式リリースなら最後に GitHub Actions の Deploy site を起動する（[Web 配布](#web-配布-github-pages--sparkle)）

それ以外 (`release/production` 以外のブランチ / PR) で起動された Archive は、`build-<ビルド番号>` タグの **prerelease** として `EisuPlus-<version>-build<ビルド番号>.zip` をアップロードする。prerelease は `install-latest.sh` の「最新リリース」には含まれない。

## リリース PR

`main` に push されると GitHub Actions (`.github/workflows/create-release-pr.yml`) が [git-pr-release](https://github.com/x-motemen/git-pr-release) で `main` → `release/production` のリリース PR を作成・更新する。PR 本文には前回リリース以降に `main` へマージされた PR がチェックリストで並ぶ。

初回のみ以下の準備が必要。

- `release/production` ブランチを作成しておく (git-pr-release は存在しないブランチへの PR を作れない)
  ```sh
  git push origin v0.1.0:refs/heads/release/production   # 直近リリースのタグから切る
  ```
- Settings → Actions → General → Workflow permissions で **Allow GitHub Actions to create and approve pull requests** を有効にする

git-pr-release は `GITHUB_TOKEN` で PR を作るので、作られた直後は Check release version が走らない (`GITHUB_TOKEN` によるイベントはワークフローを起動しない)。`main` に次の push があると走る。すぐに確かめたいときは、リリース PR を Close → Reopen する。

リポジトリを public にしたら、Settings → Rules → Rulesets で `release/production` に **Require status checks to pass** (`release-version`) を設定し、チェックが通らないとマージできないようにする (private のままでは無料プランで使えない)。

## Web 配布 (GitHub Pages + Sparkle)

アプリは https://abeyuya.github.io/EisuPlus/ で配布する。サイトのソースは `site/`。

リポジトリ名と配布 URL はアプリ名の EisuPlus に合わせているが、ターゲット・スキーム・バンドル ID (`com.github.abeyuya.EisuMod`) は旧名の EisuMod のまま (バンドル ID を変えるとアクセシビリティの許可と設定が引き継がれない)。**今後はリポジトリ名を変えない**。appcast の URL (`SUFeedURL`) は配布済みのアプリに埋め込まれていて、GitHub Pages は改名後の URL へ転送しないので、既存の利用者にアップデートが届かなくなる。

- `.github/workflows/pages.yml` (Deploy site) が `scripts/build-site.sh` でサイトを組み立てて GitHub Pages にデプロイする
  - 最新 (バージョンが最大) の正式リリースの zip に Sparkle の EdDSA 署名を付け、`appcast.xml` を書き出す。ダウンロードボタンもその zip に向ける
  - 起動するのは、`site/` などを変えて `main` に push したとき、Xcode Cloud が正式リリースの zip をアップロードし終えたとき (`repository_dispatch`)、手動で実行したとき
- アプリは Sparkle (`EisuMod/App/Updater.swift`) で `appcast.xml` を確認し、新しいバージョンがあればアップデートする。比べるのはビルド番号 (`CFBundleVersion`)
  - 同じタグで Rebuild すると、ビルド番号だけが上がるので、そのバージョンを使っている人にも同じバージョンへの更新が届く。zip が置き換わる以上 appcast の署名も作り直す必要があるので、これは避けられない。修正を出すときはバージョンを上げる
  - appcast に載せるのは、GitHub の latest ではなく、バージョン (`vX.Y.Z` のタグ) が最大の正式リリース。手でタグを付けて旧系統の hotfix を出しても、新しい系統の利用者に古いバージョンが配られることはない

### 初期設定 (初回のみ)

1. Sparkle の鍵を作る。秘密鍵はログインキーチェーンに保存され、公開鍵が表示される
   ```sh
   xcodegen generate -q && xcodebuild -project EisuMod.xcodeproj -scheme EisuMod -derivedDataPath build -resolvePackageDependencies
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
2. 公開鍵を `project.yml` の `SUPublicEDKey` に書き、`xcodegen generate` して `EisuMod/Info.plist` もコミットする
   - 空のままだと、Sparkle が起動時に「アップデートを確認できない」というエラーを出す
3. 秘密鍵を GitHub Actions の Secret `SPARKLE_PRIVATE_KEY` に登録する
   ```sh
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x /tmp/sparkle_private.key
   gh secret set SPARKLE_PRIVATE_KEY < /tmp/sparkle_private.key && rm /tmp/sparkle_private.key
   ```
   - **秘密鍵をなくすと、配布済みのアプリにアップデートを届けられなくなる**。キーチェーンの「ed25519」(Private key for signing Sparkle updates) をパスワードマネージャなどにも控えておく
4. リポジトリの Settings → Pages → Build and deployment → Source を **GitHub Actions** にする
   - private リポジトリで Pages を使うには有料プランが必要。また、private のままだと Release の zip を他の人がダウンロードできない。**公開はリポジトリを public にしてから**
5. Xcode Cloud の `GITHUB_RELEASE_TOKEN` は Contents: Read and write があれば `repository_dispatch` も送れるので、追加の設定はいらない

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
  - Repository access: `abeyuya/EisuPlus` のみ
  - Permissions: Contents → Read and write
- Developer ID Application 証明書を `.p12` で書き出す: `./scripts/export-developer-id-p12.sh` を実行すると、`DEVELOPER_ID_P12_BASE64` と `DEVELOPER_ID_P12_PASSWORD` の値が順にクリップボードに入る (ファイルは残らない)
  - Xcode Cloud は Developer ID 版を書き出さず (Distribution Preparation に Developer ID がない)、API キーでは Developer ID のクラウド署名もできない。そのため `ci_post_xcodebuild.sh` がこの証明書で archive から Developer ID 版を書き出す

### 2. ワークフローの作成

1. `xcodegen generate` して `EisuMod.xcodeproj` を Xcode で開く
2. Integrate → Create Workflow… (GitHub 連携と App Store Connect のアプリ登録を求められたら従う)
3. ワークフローを編集
   - Start Conditions: **Branch Changes** に `release/production` を含める (正式リリースはこのビルドから作る)。ほかのブランチのビルドも prerelease として欲しければ足す
     - **Tag Changes** は追加しない。追加すると Tag a release が付けたタグでもう一度ビルドされ、同じリリースの zip がビルド番号違いのもので置き換わる
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
