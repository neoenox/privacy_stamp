# Privacy Stamp

Privacy Stamp は、画像内の機微な領域を手動でマスクし、共有前に別PNGとして書き出すことを目的とした Flutter MVP です。画像処理はアプリ / ブラウザ内のローカル処理を基本とします。

## 現在できること

1. JPEG / PNG / WebP を1枚選択
2. 画像をローカルpreview
3. 顔・文字・バーコードの候補を自動でマスク（Android実機、オンデバイスML Kit）
4. 不透明な矩形maskを追加
5. maskを移動・resize・削除
6. 元画像を上書きせず、別PNGとしてexport

export時はorientationを焼き込み、metadata除去を検証します。顔・文字・バーコード検出は縮小した向き補正済みコピーに対して行い、結果を正規化座標で元画像へ戻します。

## 現在できないこと

自動検出は目安であり、カバレッジ保証はありません。

- 自動maskだけに依存した安全保証

顔・文字・バーコードのAndroid用検出器は実装済みです。現在の候補ビルドでの実機受入は別途必要です。**現時点では手動レビューが必須**です。

## Privacy boundary

現在のアプリコードは、選択画像をローカルDartコードと `image` packageでdecode / mask / encodeします。

- application serverなし
- upload APIなし
- analytics SDKなし
- remote detector integrationなし
- source画像とexport PNGを分離
- export PNGを再decodeしてmask pixel / metadataをtest可能

ただし、これは完全なsecurity / privacy certificationではありません。false negative、OS / browser compromise、malicious file、dependency compromise、deployment設定などは別リスクです。

## Android / Web

### Android

- Flutter launcherとローカル画像処理を提供
- production application IDは `com.privacy_stamp`
- release signing配線とrunbookあり
- production upload key / Play Console受入は別のprivileged gate

### Web

- Flutter web shellとlocal file picker flowを提供
- automatic detector adapterは未実装
- deployed hostのnetwork / storage / browser behaviorは別途受入が必要

プラットフォームplugin変更時は、permissionとnetwork egressを再監査してください。

## Development

Dart 3.12以上を含むFlutter SDKを使用します。

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test --reporter expanded
flutter build web --release
flutter build apk --debug
git diff --check
```

テストはrule engine、coordinate mapping、opaque masking、metadata stripping、controller race、exported pixel reinspection等を対象にします。

## Acceptance

CI成功だけでrelease可能とは扱いません。特に次を別ゲートとして確認します。

- deterministic synthetic high-resolution image
- low-memory Android環境でのselect / pan / zoom / mask / export
- input GPSあり / output GPSなし
- output pixel count一致
- OOM / ANR / process deathなし
- cancel / back / lifecycle安全性
- browser / deployed-host behavior
- production signing / Play Console

private写真、private path、実GPS値を受入証跡へ残さないでください。

## Release

正式ID、release signing配線、手順は [docs/RELEASE.md](docs/RELEASE.md) を参照してください。

Production upload keyの作成・保管、Play App Signing、store listing、Data safety、internal testはowner credentialを伴う別作業です。

## 主な資料

- [MVP_STATUS.md](MVP_STATUS.md) — 実装 / release checklist
- [docs/RELEASE.md](docs/RELEASE.md) — Android release手順
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) — third-party license情報

## 作業管理

READMEには変動しやすいcurrent SHA、個別PR、acceptance結果を固定しません。最新のsynthetic高解像度受入、release signing、Play blockerは GitHub Issues / Pull Requests を正としてください。
