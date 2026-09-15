# InfinitStreamer for iOS

[infinit-streamer](https://github.com/nmt3325/infinit-streamer)（Android）の **機能面** を iOS で再現したアプリです。Android 版のコードを移植したものではなく、同じ目的を Swift / SwiftUI + HaishinKit で独自に実装しています。

## メイン機能: YouTube への永久配信

1. Google アカウントにサインイン（PKCE による OAuth、スコープは `https://www.googleapis.com/auth/youtube`）。
2. `liveBroadcasts.insert` で新規ライブを作成（`recordFromStart: true` / `enableDvr: true` なので **アーカイブが残る**）。
3. `liveStreams.insert` + `liveBroadcasts.bind` で RTMP 取り込み先を用意し、端末のカメラ・マイクを送出。
4. **11 時間 55 分（42,900 秒）** 経過するごとに、
   - 切り替えの 90 秒前に次のライブと RTMP ストリームを事前作成
   - 新しいエンドポイントへ publish を切り替え
   - 直前のライブを `transition(complete)` で終了してアーカイブを確定
5. これを **無限ループ** で繰り返すため、配信は途切れず、11 時間 55 分ごとのアーカイブが YouTube 上に積み上がります。

YouTube のライブ配信は 1 本あたり 12 時間が上限のため、5 分の余裕を持たせた 11 時間 55 分をローテーション間隔にしています。

### 実装の中心

| ファイル | 役割 |
| --- | --- |
| `Sources/InfinitStreamer/Session/RotationPlan.swift` | ローテーション間隔・事前作成タイミング・再試行バックオフ（純粋ロジック、テスト対象） |
| `Sources/InfinitStreamer/Session/SessionCoordinator.swift` | 無限ループ本体（作成 → 送出 → 切り替え → 旧配信終了） |
| `Sources/InfinitStreamer/YouTube/YouTubeClient.swift` | YouTube Data API v3（liveBroadcasts / liveStreams / bind / transition） |
| `Sources/InfinitStreamer/Streaming/RTMPPublisher.swift` | HaishinKit による RTMP 送出と配信先の切り替え |
| `Sources/InfinitStreamer/Auth/GoogleAuth.swift` | PKCE OAuth、トークン更新、Keychain 保存 |

## セットアップ

1. Google Cloud で YouTube Data API v3 を有効化し、**iOS 用 OAuth クライアント**を作成します。
2. `project.yml` の以下 2 箇所を自分のクライアント ID に置き換えます。
   - `GoogleOAuthClientID`: `1234-abc.apps.googleusercontent.com`
   - `CFBundleURLSchemes`: `com.googleusercontent.apps.1234-abc`（逆順形式）
3. プロジェクトを生成してビルドします。

```sh
brew install xcodegen
xcodegen generate
open InfinitStreamer.xcodeproj
```

実機で配信する場合は、

- 低電力モードを無効化し、電源に接続したままにしてください（画面スリープはアプリ側で抑止しています）。
- バックグラウンドでの長時間配信は iOS の制約を受けます。安定運用はフォアグラウンド + 電源接続が前提です。

## GitHub Actions

`.github/workflows/ios.yml` が push / PR / 手動実行で自動ビルドします。

- XcodeGen でプロジェクト生成
- iOS Simulator 向けビルド
- ユニットテスト（ローテーションロジック）
- 署名なし `.ipa` をアーティファクトとしてアップロード

## 制約

- 配信の公開設定は `AppConfig.privacyStatus`（既定 `public`）で変更できます。
- 切り替え時に数秒の断が発生します（新規ライブへの publish 切り替えのため）。
- YouTube 側のクォータ・ライブ配信有効化（チャンネルの権限）が必要です。
