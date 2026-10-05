# SpecQR GDScript

Godot 標準エンジンで動く、依存パッケージ不要の QR コード生成ライブラリです。QR のビット列、GF(256)、Reed–Solomon、行列配置、マスク評価、SVG、PNG は GDScript でフルスクラッチ実装しています。外部 QR ライブラリ、JavaScript、FFI、GDExtension、エディタプラグインは使いません。

**Godot は必須ランタイムです。** GDScript 単独の汎用インタプリタでは動きません。Godot 4.3 以上の標準版を対象とし、公式 Godot 4.3 と 4.7.2 の Linux x86-64 で検証します。.NET 版や C# は不要です。Windows/macOS、Web エクスポート、モバイルを実測済みとは扱いません。

- QR Model 2、バージョン 1–40、ECC L/M/Q/H、全 8 マスクと自動選択
- 数字・英数字・バイト・漢字、混在セグメント最適化、ECI、FNC1 第一／第二位置
- 行列を作らない事前計画、容量照会、マスク・色・印刷・読み取りリスク診断
- GS1 要素文字列、50 AI、チェックディジット、Digital Link
- Structured Append 2–16 シンボル、分割、手動セグメント、復号結果の結合検査
- SVG、RGBA8、フルスクラッチ PNG、data URL、Godot Image、ヘッドレス CLI

## インストール

このリポジトリの `addons/specqr` フォルダを、既存の Godot プロジェクトの `addons/specqr` へコピーしてください。プラグインの有効化・外部パッケージのインストール・ビルドは不要です。

```gdscript
const QR = preload("res://addons/specqr/specqr.gd")

func _ready():
    var qr = QR.generate("こんにちは、SpecQR", {"eci": true})
    if QR.is_error(qr):
        printerr(qr.code + ": " + qr.message)
        return
    var png = QR.to_png(qr)
    if QR.is_error(png):
        printerr(png.code + ": " + png.message)
        return
    var file = FileAccess.open("user://hello.png", FileAccess.WRITE)
    if file != null:
        file.store_buffer(png)
        file.close()
```

エラーは例外ではなく、`{error, isSpecQRError, code, message}` の Dictionary で返します。戻り値を使う前に `QR.is_error()` で確認してください。`plan()` は正常な「容量不足」を `ok == false` で返すため、エラー確認後に `ok` も確認します。

## 文字列とバイト

```gdscript
var text_qr = QR.generate("漢字🙂", {"eciAssignment": 26})
var binary_qr = QR.generate(PackedByteArray([0, 1, 127, 128, 255]))
```

文字列は Godot の Unicode `String`、バイナリは整数 `Array` または `PackedByteArray` です。ECI は文字コードの宣言で、変換処理ではありません。

**Godot String は U+0000 を保持できません。** テキストの NUL は対応外です。厳密な UTF-8 入力ヘルパー・CLI・JSON 検証プロトコルは NUL を拒否します。NUL を含む内容はバイト配列として渡してください。エンジンが先に削除・置換した文字はライブラリから検出できません。この差分を含む 8 個の共有ケースは除外せず、明示した期待エラーで検証します。

## CLI

リポジトリのルートで実行します。`godot` は標準エンジンの実行ファイルです。

```sh
godot --headless --no-header --path . --script script/cli.gd -- --text 'Hello, SpecQR' --output hello.svg
godot --headless --no-header --path . --script script/cli.gd -- --text-file message.txt --eci 26 --format png --output message.png
godot --headless --no-header --path . --script script/cli.gd -- --bytes-file payload.bin --format png --output payload.png
godot --headless --no-header --path . --script script/cli.gd -- --text '1234567890' --plan
```

既定値は ECC M、余白 4 モジュール、倍率 8。PNG は `--output` 必須です。テキスト形式だけ標準出力へ出せます。入力は明示した文字列・ファイルを読み、`-` を標準入力として解釈しません。エラー時は標準エラーへ 1 行、終了コード 2 を返します。

GS1 / Digital Link は ASCII HTTP(S) の一般的な URL 補正に対応します。Unicode ホストの IDNA/UTS46 は未対応で、不正な percent/UTF-8 データは置換せず拒否します。詳細な互換性差分は GS1 ガイドに明記しています。

## ドキュメント

- [日本語 Getting Started](docs/getting-started.md)
- [English API reference](docs/reference.md)
- [GS1 / Digital Link の対応範囲](docs/gs1.md)
- [検証・ランタイム・差分](docs/verification.md)
- [別プロジェクトへのコピー例](examples/consumer_project/README.md)

MIT ライセンス。SpecQR の既存版を参照したネイティブ実装です。GitHub でソースを配布し、Godot Asset Library への登録やタグ付きリリースを前提にしません。
