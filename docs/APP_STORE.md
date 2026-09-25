# Mac App Store での配布

自分用ビルド（`EisuMod` ターゲット）とは別に、Mac App Store 用の `EisuMod-AppStore` ターゲットを用意している。ソースは共通。

アプリ名（表示名と `.app` の名前）は **EisuPlus**。ターゲット・スキーム・バンドル ID（`com.github.abeyuya.EisuMod`）・リポジトリ名は旧名の EisuMod のまま。

| | `EisuMod`（自分用） | `EisuMod-AppStore` |
|---|---|---|
| 署名 | 自動署名（Xcode Cloud で Developer ID 署名・公証。ローカルは `scripts/install.sh` で Developer ID に上書き） | Apple Distribution（自動署名） |
| App Sandbox | なし | あり（`Config/EisuMod-AppStore.entitlements`） |
| コンパイル条件 | なし | `APP_STORE` |
| 隣のデスクトップへ運ぶ | あり | **なし**（非公開 API の SkyLight と `_AXUIElementGetWindow` を使うため） |
| 配布 | GitHub Release（Xcode Cloud） | App Store Connect（Xcode Cloud。手元からは `scripts/archive-appstore.sh`） |

どちらも同じ Xcode Cloud のワークフローでビルドする（[RELEASE.md](RELEASE.md)）。`ci_post_xcodebuild.sh`（公証と GitHub Release）は `EisuMod` スキームのときだけ動く。

非公開 API を使う機能を追加するときは `#if !APP_STORE` で囲むこと（App Review のガイドライン 2.5.1 で却下される）。

## サンドボックス内での動作

App Sandbox 内でも、アクセシビリティ権限があれば以下はそのまま動く。

- アクティブな CGEventTap（イベントの握りつぶしを含む）
- `CGEvent.post` によるキーイベントの送出（英数/かな）
- AX による他アプリのウィンドウの移動・リサイズ
- `SMAppService.mainApp` によるログイン時の起動
- 除外アプリの選択（`NSOpenPanel`。`files.user-selected.read-only` で読める）

設定（UserDefaults）はサンドボックスのコンテナに保存されるので、自分用ビルドの設定は引き継がれない。

## ローカルでサンドボックス版を試す

Apple Distribution 証明書がなくても、Developer ID で署名すれば試せる。バンドル ID と署名者が同じなので、アクセシビリティ権限は自分用ビルドのものが引き継がれる。

```bash
xcodegen generate -q && xcodebuild -project EisuMod.xcodeproj -scheme EisuMod-AppStore -configuration Release -derivedDataPath build-mas -quiet build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application"
```

## 申請までの手順

### 1. 初回だけ（Apple Developer / App Store Connect）

1. Xcode の Settings > Accounts に個人の Apple ID（Team `37XL3EDJ44`）を追加する
2. [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) で App ID `com.github.abeyuya.EisuMod` を登録する（`-allowProvisioningUpdates` で自動登録されることもある）
3. [App Store Connect](https://appstoreconnect.apple.com/) で新規 macOS アプリを作る
   - 名前: `EisuPlus`
   - バンドル ID: `com.github.abeyuya.EisuMod`
   - SKU: 任意（例: `eisumod`）
   - カテゴリ: ユーティリティ（`LSApplicationCategoryType` と合わせる）
4. App Store Connect に入力するもの
   - スクリーンショット（1280×800 / 1440×900 / 2560×1600 / 2880×1800 のいずれか。最低1枚）
   - 説明文、キーワード、サポート URL
   - **プライバシーポリシーの URL**（必須。データを収集しない旨のページでよい）
   - App のプライバシー: 「データを収集していません」
   - 価格と配信地域

### 2. Xcode Cloud のワークフローに App Store 版を足す（初回だけ）

Developer ID 版をビルドしている既存のワークフローを編集する（Xcode の Integrate > Manage Workflows…、または App Store Connect の Xcode Cloud タブ）。

1. Actions の「+」から **Archive** を追加する
   - Platform: macOS
   - Scheme: `EisuMod-AppStore`
   - Deployment Preparation: **TestFlight and App Store**
2. 必要なら Post-Actions に **TestFlight Internal Testing** を追加し、自分をテスターにする

これで `release/production` が伸びるたびに、Developer ID 版（GitHub Release）と App Store 版（App Store Connect）の両方がビルドされる。
署名（Apple Distribution 証明書とプロビジョニングプロファイル）は Xcode Cloud のクラウド署名が行う。

### 3. リリースのたび

1. `project.yml` の `MARKETING_VERSION` を上げてから `release/production` へマージする
   - ビルド番号（`CURRENT_PROJECT_VERSION`）は `ci_post_clone.sh` が `CI_BUILD_NUMBER` で上書きするので触らなくてよい
   - ブランチ起動のビルドではタグからバージョンが決まらない。審査を通ったバージョンのままアップロードすると App Store Connect に拒否され、App Store 版の Archive アクションが失敗する
2. App Store Connect の TestFlight にビルドが届いたら、新しいバージョンを作ってビルドを選び、審査へ提出する

手元からアップロードする場合は `./scripts/archive-appstore.sh --upload`（`CURRENT_PROJECT_VERSION` を Xcode Cloud のビルド番号より大きくしておくこと）。`--upload` なしなら `build-mas/export/` に `.pkg` を書き出すだけ。

## 審査対策

アクセシビリティ権限を要求するアプリは、用途を審査メモ（App Review Information > Notes）で説明しないと却下されやすい。以下を英語で書いておく。

```text
EisuPlus is a menu bar utility for keyboard and window management.

Why it needs the Accessibility permission:
- To detect a single press of the left/right Command key and switch the input source to
  Eisu (English) / Kana (Japanese), it uses a CGEventTap and posts the JIS Eisu/Kana key events.
- To move and resize the window under the mouse cursor while a modifier key is held
  (Control + mouse move = move, Option + mouse move = resize), and to snap windows to the
  left/right half or maximize them at the screen edges, it uses the Accessibility API
  (AXUIElement position/size attributes).

How to test:
1. Launch the app. It appears in the menu bar (keyboard icon) and asks for the Accessibility permission.
2. Grant it in System Settings > Privacy & Security > Accessibility.
3. Hold Control and move the mouse over a window: the window follows the cursor.
   Move it to the left/right edge and release Control: it snaps to half of the screen.
4. Hold Option and move the mouse: the window resizes from the bottom-right corner.
5. Press and release the left Command key alone: the input source switches to English.
   The right Command key switches to Japanese (Kana).

The app does not collect, store, or transmit any user data. Keystrokes are only inspected
in memory to detect a single Command key press and are never logged or recorded.
```

### 却下されうる点

- **アクセシビリティ API の用途**: ウィンドウ管理アプリ（Magnet など）は同じ方式で App Store に並んでいるので、用途の説明があれば通る見込みが高い
- **キー入力の監視**: イベントタップでキー入力を見ていることを「キーロガー」と誤解されないよう、上のメモのとおり記録しないことを明記する
- **初回起動時の権限ダイアログ**: 起動直後に `AXIsProcessTrustedWithOptions` でシステムのダイアログを出している。「何のための権限かを先に説明せよ」（ガイドライン 5.1.1）と言われた場合は、説明用のウィンドウを挟む
