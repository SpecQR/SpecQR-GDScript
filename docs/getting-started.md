# Getting Started

## 1. 必須ランタイムと配置

Godot 4.3 以上の標準エンジンを用意し、`godot --version` で確認します。検証対象は公式 Linux x86-64 の 4.3 と 4.7.2 です。GDScript の実行には Godot が必要で、「依存なし」は Godot 以外の実行時パッケージが不要という意味です。

`addons/specqr` 全体を自分の Godot プロジェクトへコピーします。`specqr.gd` は公開ファサード、残りのファイルはその内部実装です。一部だけをコピーしないでください。`preload("res://addons/specqr/specqr.gd")` で読み込めます。プラグイン設定は不要です。

## 2. 生成、計画、保存

```gdscript
const QR = preload("res://addons/specqr/specqr.gd")

func make_qr():
    var plan = QR.plan("1234567890HELLO", {"maxVersion": 3})
    if QR.is_error(plan):
        return plan
    if not plan.ok:
        return {"reason": "指定した容量に入りません"}
    var qr = QR.generate("1234567890HELLO")
    if QR.is_error(qr):
        return qr
    return QR.to_png(qr) # PackedByteArray またはエラー Dictionary
```

`plan` はコードワード・行列を作りません。容量不足そのものは `ok == false` の正常な計画結果です。`generate` は容量不足で `DATA_TOO_LONG` を返します。`to_png` の戻り値は `FileAccess.store_buffer()` で保存します。SVG は `store_string()` で保存できます。

```gdscript
var image = QR.to_image(qr) # Image またはエラー Dictionary
```

`to_image` はライブラリの RGBA ピクセルを Godot Image に変換するだけです。PNG の生成アルゴリズムはエンジンの PNG エンコーダへ委譲していません。

## 3. 入力の型

```gdscript
var text_qr = QR.generate("漢字とひらがな🙂", {"eci": true})
var binary_qr = QR.generate([0, 255, 128, 0])
var text_segment = QR.new_segment("byte", "Unicode テキスト")
var raw_segment = QR.byte_segment(PackedByteArray([0, 255]))
var capacity = QR.get_capacity(1, "L", "numeric")
var manual = QR.generate_segments([
    QR.numeric("1234567890"),
    QR.new_segment("byte", "lowercase")
])
```

オプションのキーは `String` / `StringName` を受け付け、通常の文字列キーへ正規化します。Godot の辞書のドット記法でも設定できます。値の型は厳密です。数値オプションに数値文字列や `true` は使えません。真偽値オプションには `true` / `false` を使います。バイトは有限の整数 0–255。積分値の `float` も範囲検査後に受け付けます。文字列とバイトを自動で取り違えません。

外部 UTF-8 は `QR.decode_utf8(bytes)` で検査できます。最短表現、Unicode scalar、切断、NUL を確認します。Godot String 自体は U+0000 を保持できないため、NUL は必ずバイナリ経路を使ってください。

## 4. GS1 と FNC1

```gdscript
var elements = [
    {"ai": "01", "value": "09506000134352"},
    {"ai": "10", "value": "LOT1"}
]
var raw = QR.create_gs1_element_string(elements)
var qr = QR.generate(raw, {"gs1": true})
var link = QR.create_gs1_digital_link(elements)
```

各呼び出しのエラーを確認してください。高水準の FNC1 入力では `%` は文字どおりのパーセント、U+001D は区切りです。英数字セグメントの `%` は `%%` に変換し、GS はバイトモードで保ちます。GS を含む入力で英数字モードを強制すると拒否します。手動英数字セグメントでは利用者が QR 表現に従い、区切り `%`、文字どおりのパーセント `%%` を渡します。

## 5. Structured Append

```gdscript
var set = QR.generate_structured_append("x".repeat(100), {
    "version": 1, "errorCorrectionLevel": "L"
})
if not QR.is_error(set):
    for symbol in set.symbols:
        var png = QR.to_png(symbol)
```

同じ version/ECC で 2–16 個に分割します。一つに収まる場合は通常の `generate` を使います。ECI、FNC1、GS1、ECC 自動強化とは併用できません。

`merge_structured_append_parts` は、別の復号器から取得した `{index,total,parity,data}` の配列を受け取ります。インデックスは 1 始まりで、順序・欠落・重複・パリティを確認します。文字列とバイト配列は混在させません。このライブラリ自体は QR の復号器ではありません。

## 6. 診断とサイズ

`QR.diagnostics(result)` は独立した診断スナップショットを返します。余白・色・透明度・容量・印刷時のモジュール寸法を確認できます。既定の余白 4、倍率 8 を推奨しますが、すべてのカメラや復号器の読み取りを保証するものではありません。

描画は最大 4,194,304 ピクセル、辺 2048 までです。入力や色、出力サイズにも上限があり、大きな描画配列を確保する前に検査します。
