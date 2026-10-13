<a id="english-api-reference"></a>

# API リファレンス

SpecQR provides native GDScript APIs for generating and rendering QR codes, planning segments, and working with GS1 and Structured Append. This reference describes their contracts and limits.

## Runtime and installation

SpecQR 0.1.0 は、標準の Godot 4.3 以降で動くネイティブの GDScript 実装です。Godot は実行に必須のホストです。外部 QR パッケージ、JavaScript 実行環境、FFI、GDExtension、エディタープラグイン、.NET 実行環境は使いません。`addons/specqr` ディレクトリ全体をプロジェクトへコピーし、`res://addons/specqr/specqr.gd` をプリロードしてください。Linux x86-64 で検証したエンジンは公式の 4.3 と 4.7.2 です。他の OS と Web・モバイルへのエクスポートは検証済みとしていません。

公開ファサードのメソッドはすべて静的です。成功時には、以下に記載する通常の Dictionary、Array、String、PackedByteArray、またはネイティブの Image を返します。想定される失敗はエラーの Dictionary として返すため、結果を使う前に `QR.is_error(result)` で確認してください。Dictionary のキーには String または StringName を使えます。Godot のドット構文で作成したキーも含み、オプションの受付時と診断情報のコピー時に、内部で所有する String キーへ正規化します。他の型のキーと正規化後に重複するキーは拒否します。値には以下の厳密な契約を適用します。未知のオプション名も拒否します。公開セグメントコンストラクターと生成処理は利用者のペイロードをコピーします。結果の Dictionary は変更可能なので、返された結果は呼出側が所有する値として扱ってください。

## Text, bytes, errors

テキストは Godot の Unicode `String` です。生のバイト列は、0..255 の整数値を持つ Array または PackedByteArray です。`new_segment("byte", text)` は UTF-8 テキスト、`byte_segment(bytes)` は内容を解釈しないバイナリを表します。`encode_utf8(text)` はバイトの Array を返します。`decode_utf8(bytes)` は最短形式を要求する厳密な UTF-8 復号を行い、サロゲート、U+10FFFF を超える値、途中で切れた列、NUL を拒否します。

Godot の String は U+0000 を保持できません。ホストがすでに削除または置換した後では、この制限を補正できません。CLI、明示的な UTF-8 デコーダー、JSON テストの入力境界では NUL を拒否します。バイナリ入力では、ゼロを含む全 256 種類のバイト値を損失なく扱えます。このホストの違いを理由に fixture を黙って除外することはありません。

整数の設定値には、記載された範囲内の Godot の `int`、または有限で整数値の `float` を受け付けます。数値に見える文字列や真偽値は受け付けません。真偽値の設定には `bool` が必要です。文書化された ECI の真偽値エイリアスは例外で、`eci: true` は割当て番号 26、false は指定なしを意味します。ECI はエンコーディングの宣言であり、データの文字コード変換は行いません。

エラーのフィールドは `error: "SpecQRError"`、`isSpecQRError: true`、`code`、`message` です。GS1 エラーには `detailCode` も含みます。コードには `INVALID_INPUT`、`INVALID_MODE`、`INVALID_ECC_LEVEL`、`INVALID_VERSION`、`INVALID_ECI`、`INVALID_COLOR`、`INVALID_OUTPUT`、`INVALID_GS1`、`DATA_TOO_LONG`、CLI の `IO_ERROR` があります。メッセージの文言は説明用で、互換性を判定するキーではありません。

## Generation and planning

- `generate(text_or_bytes, options = null)`
- `generate_segments(segments, options = null)` は明示した境界を保持します。
- `plan(text_or_bytes, options = null)` と、そのエイリアス `estimate`。
- `plan_segments(segments, options = null)` と、そのエイリアス `analyze_segments`。
- `get_capacity(version, ecc = "M", mode = "", control_bits = 0)` は、`version`、`errorCorrectionLevel`/`errorCorrection`、`mode`、`controlBits` を持つ Dictionary も受け付けます。
- `diagnostics(result)` は、検証済みで独立した JSON 互換のスナップショットを返します。
- `size(qr)`、`module_at(qr, x, y)` は、0 始まりの座標を使います。

QR の結果は `matrix`（0/1 を格納する正方形の Array）、`version`、`maskPattern`、`errorCorrectionLevel`、`dataCodewords`、`codewords`、`segments`、`options`、`diagnostics` を含みます。

計画は `ok`、`version`、`capacityVersion`、`errorCorrectionLevel`、`requestedErrorCorrectionLevel`、`boostedErrorCorrection`、`dataBitLength`、`capacityBits`、`remainingBits`、`segments`、`diagnostics` を含みます。入力は有効でも容量に収まらない自動計画では `ok=false`、`version=0` となり、`capacityVersion` は最後に調べた容量を示します。計画処理はコード語や行列を生成しません。生成処理は、選択した範囲に収まらなければ `DATA_TOO_LONG` を返します。

### Options

| キー | 既定値 | 契約 |
| --- | --- | --- |
| errorCorrectionLevel | M | L、M、Q、H のいずれか |
| version | 0 | 0 または `"auto"`。固定値は 1..40 |
| minVersion, maxVersion | 1, 40 | 順序の整った自動探索範囲 |
| maskPattern | -1 | -1 または `"auto"`。固定値は 0..7 |
| mode | auto | auto, numeric, alphanumeric, byte, kanji |
| optimizeSegments | true | 混合モードでビット数を最小にするセグメント分割 |
| allowKanji | true | 自動最適化で Kanji を使用 |
| boostErrorCorrection | false | バージョンを増やさずに ECC を引き上げる |
| eciAssignment | -1 | -1 は指定なし。それ以外は 0..999999 |
| gs1, fnc1 | false | 検証を伴う GS1、または検証を伴わない FNC1 第 1 位置 |
| fnc1Second | 空の String | ASCII 数字 2 桁またはラテン文字 1 文字 |
| structuredAppend | null | index、total、parity を持つヘッダー |
| margin, scale | 4, 8 | margin は 0..1e9 の整数、scale は 1..1e9 の整数 |
| foreground, background | #000000, #ffffff | 安全な 16 進表記または単純な ASCII の CSS 色 |
| printDpi | null | 有限の正数で、寸法も有限の正数になる値 |

`errorCorrection` は `errorCorrectionLevel` のエイリアスで、競合する指定は失敗します。`eci` は数値の割当て番号または真偽値のエイリアスを受け付けます。`encoding` は大文字と小文字を区別しない `utf-8` だけに対応します。`output` は互換性のため matrix/svg/svg-data-url/png/png-data-url を受け付けますが、生成結果の型は変わりません。レンダラーを明示的に呼び出してください。`diagnostics` は真偽値として検証し、診断情報は結果に保持します。

## Data and control segments

コンストラクター: `numeric(text)`、`alphanumeric(text)`、`kanji(text)`、`new_segment(mode,text)`、`byte_segment(bytes)`、`eci(assignment)`、`fnc1()`、`fnc1_second(indicator)`、`structured_append_segment(index,total,parity)`。

検査用 API: `mode`、`is_control`、`is_binary`、`text`、`logical_bytes`、`segment_count`/`count`、`character_count`、`byte_count`、`assignment_number`、`application_indicator`、`application_indicator_codeword`、`index`、`total`、`parity`、`bit_length(segment,version)`、`bits(segment,version)`、`normalize_segments`、`segments_bit_length`、`segments_bits`。

制御セグメントには順序と一意性の規則があり、異なる制御系統は併用できません。SA の index は 1 始まり、total は 2..16 です。手動セグメントで高水準の GS1 オプションを使うことは拒否します。明示的な `fnc1()` セグメントを使ってください。Kanji は、固定した SpecQR 基準版から保存した 6,953 組の対応表を使い、ホストのコーデックには依存しません。

高水準の FNC1 は、文字としての `%` をデータ、U+001D を区切りとして扱います。alphanumeric では文字としての百分率記号を `%%` に変換します。自動最適化は、このエスケープを行う候補と、損失のない byte 符号化を比較します。GS を含む入力で alphanumeric を強制することは拒否します。手動の alphanumeric セグメントには、呼出側が用意した QR FNC1 の表現をそのまま使います。`%` は区切り、`%%` は文字としての百分率記号です。手動の byte セグメントは内容を解釈しません。

## Rendering and native Image

`to_svg`、`to_png`、`to_pixels`、`to_svg_data_url`、`to_png_data_url`、`to_image` は、QR の結果または QR サイズの行列（21..177 のうち有効な QR 寸法）と、省略可能なレンダリング専用オプションを受け付けます。上書きできるキーは `margin`、`scale`、`foreground`、`background` だけです。上書きを指定した場合、省略したレンダリングのキーには既定値を使います。

SVG は ASCII テキストです。PNG は、RGBA8、filter 0、非圧縮の DEFLATE ブロック、独自実装の CRC32/Adler32 を使う PackedByteArray です。`to_pixels` は `{width,height,pixels}` を返し、pixels は行優先の RGBA PackedByteArray です。`to_image` はこのピクセル列から通常の Godot Image を作ります。PNG の符号化は Godot へ委ねません。PNG の保存にはバイナリの `FileAccess.store_buffer` を使ってください。

ラスターの色は #rgb、#rgba、#rrggbb、#rrggbbaa、black、white、transparent に対応します。他の安全な ASCII の CSS 色名は SVG 専用で、診断ではコントラストが不明であることを示します。`parse_color(color, strict=true)`、`contrast_ratio(rgba,rgba)`、`render_dimensions(qr_or_matrix, options=null, dpi=null)` を利用できます。DPI は診断用の物理寸法に使い、PNG の pHYs フィールドへ埋め込むものではありません。

上限は、ペイロード 1,000,000 単位、手動セグメント 16,384 個、単一シンボル入力の最適化では 7,089 スカラー、ラスター 4,194,304 ピクセルかつ一辺 2048 以下、SVG の文字数 8 MiB、データ URL の文字数 32 MiB です。QR シンボルの実際の容量には、これよりはるかに小さい別の上限があります。不正な寸法や上限を超える寸法は、ラスターを確保する前に拒否します。

## Structured Append

`generate_structured_append(input, options=null, maximum=16, include_diagnostics=false)` は `{symbols,total,parity,inputLength,byteLength,diagnostics}` を返します。全シンボルはバージョンと ECC を共有し、マスクは別々に選べます。自動選択は、2..16 シンボルに収まる最小のバージョンを探します。テキストは Unicode スカラーの境界、バイナリはバイトの境界で分割します。パリティは元の UTF-8 バイト列または内容を解釈しないバイト列の XOR です。

`generate_segments_structured_append(segments, options=null, maximum=16, include_diagnostics=false, detail="summary", results=null)` は、byte 以外のセグメントを分割せず、byte セグメントを適切なスカラーまたはバイトの境界で分割します。`detail="full"` は分割単位の完全な診断情報を含めます。`results` には `"output"` または `"diagnostics"` を指定できます。

高水準の SA は、空の入力、単一シンボルに収まる入力、既存の SA ヘッダー、ECI/FNC1/GS1、ECC の引き上げを拒否します。呼出側で管理するセットには、低水準の SA ヘッダーを引き続き使えます。

`merge_structured_append_parts(parts)` は、復号済みの `{index,total,parity,data}` を受け付けます。全 index が欠落も重複もなく揃うこと、メタデータの一致、テキストとバイナリの型が混在しないこと、XOR パリティを検証し、`{data,total,parity,parts,diagnostics}` を返します。画像の復号は行わず、デコーダー固有の拡張も前提にしません。パリティ用の補助関数は `calculate_structured_append_parity`、`calculate_structured_append_segments_parity` です。

## Low-level namespaces

ファサードは `Core`、`Tables`、`Optimizer`、`Segments`、`Render`、`GS1`、`StructuredAppend`、`API`、`Error` を公開します。`Core` は GF/RS・配置・マスクのメソッド、`Tables` は QR の容量・アライメント・文字数指示子の幅を含みます。`Optimizer` には検証済みの増分トラッカーがあります。先頭がアンダースコアのメソッドは実装の詳細です。通常のアプリケーションには高水準のファサードを使ってください。

GS1 URL の正規化は、一般的な ASCII HTTP(S) の補正、検証を伴う IPv4/IPv6 の正規化、userinfo の保持に対応します。Unicode ホストの IDNA/UTS46 と、不正なパーセント符号化・UTF-8・NUL の厳密な扱いには、明記した制限があります。[GS1 プロファイル](gs1.md)と[検証の契約](verification.md)を参照してください。診断はリスクを説明するもので、すべてのカメラやデコーダーがすべてのシンボルを読めることを保証しません。
