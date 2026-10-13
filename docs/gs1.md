# GS1 and GS1 Digital Link

ネイティブの GDScript GS1 module は、SpecQR の範囲を限定した 50 AI のカタログを実装します。ネットワークアクセス、DNS lookup、subprocess 実行、host による URL 補正は行いません。すべての helper は公開 `SpecQR` facade から利用できます。

```gdscript
const QR = preload("res://addons/specqr/specqr.gd")
var elements = [
    {"ai": "01", "value": "09506000134352"},
    {"ai": "10", "value": "LOT-A"},
    {"ai": "17", "value": "271231"}
]
var raw = QR.create_gs1_element_string(elements)
var human = QR.gs1_to_human_readable(elements)
var uri = QR.create_gs1_digital_link(elements)
# https://id.gs1.org/01/09506000134352/10/LOT-A?17=271231
var parsed = QR.parse_gs1_digital_link(uri)
```

変換操作のたびに `QR.is_error` を確認してください。AI と値は実際の String です。先頭のゼロを保持するため、数値の値も引用符で囲みます。要素は Dictionary の Array、options は camelCase の String/StringName キーと厳密な boolean 値を持つ Dictionary です。ドット記法で作成したものを含め、StringName キーは所有する String キーへ正規化し、他のキー型は拒否します。値は指定どおり厳密な String/boolean のままです。未知の option 名は拒否します。返されるカタログ、metadata、正規化済み要素は、呼出側が所有するコピーです。

## Catalog

`get_supported_gs1_ais()` は 50 件のレコードを返します。`get_gs1_ai_info(ai)` は metadata を返し、未対応の AI には null を返します。フィールドは `ai`、`label`、`length`、`valueKind`、`checkDigitRule`、`digitalLinkRole`、`separator`、`digitalLinkPathForPrimary` です。

対応 AI: 00, 01, 02, 10, 11, 12, 13, 15, 16, 17, 20, 21, 22, 30, 37, 240, 241, 400, 410–415, 420, 422, 424, 425, 426, 3100–3105, 3200–3205, 91–99。

検証は、固定長・可変長、数字または表示可能な ASCII の値、該当する GTIN/SSCC のチェックデジット、raw の括弧と separator を確認します。要素の値は表示可能な ASCII です。この層では percent は文字どおりのデータであり、FNC1 変換は encoder が扱います。

GS1 全体の認証を示すものではありません。日付フィールドに必要なのは 6 桁の数字であり、暦上の有効な日付は要求しません。GLN 410–415 は 13 桁を要求しますが、チェックデジットは検証しません。未対応の AI は拒否し、GS1 の AI の組合せ規則をすべて適用するものではありません。

## Element strings and check digits

- `normalize_gs1_elements(input)` は要素の Array、`{elements: [...]}`、raw String、括弧付き HRI String を受け付けます
- `parse_gs1_human_readable(text)` → 要素の Array
- `parse_gs1_element_string(text)` → `{elements,hasSeparators}`
- `create_gs1_element_string(elements)` は、末尾以外の可変長フィールドの後に U+001D を挿入します
- `gs1_to_human_readable(elements)`、`gs1_element_string_to_human_readable(raw)`
- 別名: `gs1_normalize`、`gs1_from_human_readable`、`gs1_to_element_string`、`gs1_build`、`gs1_parse`
- `calculate_gs1_check_digit`、`validate_gs1_check_digit`
- `calculate_gtin_check_digit`、`append_gtin_check_digit`、`validate_gtin_check_digit`
- `calculate_sscc_check_digit`、`append_sscc_check_digit`、`validate_sscc_check_digit`

GTIN の本体は 7、11、12、13 桁、SSCC の本体は 17 桁です。計算は本体を、検証は完成した番号を受け付けます。形式が正しくチェックデジットだけが誤っている番号には false を返し、不正な形式の入力にはエラーを返します。Modulo-10 の重みは、右から左へ 3,1 と交互に適用します。

raw parser は、SpecQR の保守的な曖昧性検査を使います。separator のない末尾の可変長値に、完全な固定長 AI に見える suffix がある場合、その suffix とされるデータが数値検証に失敗するとしても、separator の欠落として拒否します。そのため、表示可能な文字からなる末尾の lot 値の一部も拒否する場合があります。そのような値を生成するときは、構造化した要素の Array または HRI を使ってください。

## Digital Link helpers

`create_gs1_digital_link(elements, options=null)` は次に対応します。

- `baseUrl`: 既定値は https://id.gs1.org
- `primaryAi`: 既定値は `"01"`。`"00"` と `"414"` にも対応します
- `pathAis`: 選択する qualifier。明示的な空の Array は qualifier を query に配置します
- `explicitPathAis`: bool。true は pathAis がなくても明示的な選択を適用します

primary 01 の qualifier 10,21,22 は、既定で path に入ります。path の順序は入力順に従い、残りの既知 query データは AI、次に値でソートします。AI の重複や不正な path 選択は拒否します。dot-only の qualifier 値は、path を要求しても query に配置します。別名は `gs1_digital_link`、`gs1_to_digital_link` です。

`parse_gs1_digital_link(uri, options=null)` は `elements`、`primary`、`pathElements`、`queryElements`、`unknownQuery` を返します。options は `primaryAi`（指定がなければ最初の literal 00/01/414 path segment を検出）と `unknownQuery`（既定値の `"preserve"`、または `"reject"`）です。符号化された primary-AI segment は検出に使いません。2–4 桁の数字の query キーは AI として扱い、対応している必要があります。未知 query の重複と順序は保持します。

`normalize_gs1_digital_link(uri, options=null)` は、唯一の mode である `mode: "specqr-deterministic"` を追加します。既知フィールドを決定的に再構築し、既定で適格な path qualifier を選び、既知 query をソートし、保持した未知のペアを元の順序で追加します。文書化した profile 内で冪等であり、決定的な IPv6 シリアライズを使います。Unicode host の IDNA/UTS46 は、実装した profile の範囲外です。

## Offline HTTP(S) normalization and explicit limits

固定した TypeScript baseline が使う一般的な ASCII HTTP(S) URL 正規化を扱います。範囲を限定した offline parser であり、完全な WHATWG/UTS46 実装、SSRF 対策、到達性検査ではありません。DNS やネットワークの操作は行いません。localhost、private address、loopback は構文として受け付けます。

正規化は次を対象とします。

- underscore や、ブラウザーが受け付けるその他の非 DNS label を含む、ASCII URL host/reg-name の大文字・小文字の正規化
- percent-encoded host の厳密な ASCII 復号。符号化された host delimiter と不正な escape は拒否
- 10 進・8 進・16 進の IPv4 表記、1–4 個の component、末尾の dot。32 bit 算術を検査し、出力は canonical dotted decimal
- bracket で囲まれた IPv6。最長の連続ゼロを圧縮し、同長なら最初を選択。小文字の hex と、dotted IPv4 tail から hex group への変換
- 先頭のゼロや空の port を含む 10 進 port 0..65535。HTTP/HTTPS の既定値は省略
- 最も右の @ による userinfo 解析と、URL 形式の user/password encoding。要求された URI 出力では既存 escape と credential byte を保持
- 先頭・末尾の ASCII control/space の除去、TAB/CR/LF の除去、不完全な、または slash が余分な HTTP(S) 構文と authority/path の backslash 補正

query データ中の backslash はデータとして残し、正規化時に符号化します。相対 URL の base は仮定せず、HTTP(S) 以外の scheme と scheme のない入力は拒否します。非空 fragment は拒否します。空 fragment は受け付け、builder は TypeScript 互換性のため空の base fragment marker を保持しますが、正規化では除去します。空の base query は受け付け、非空の base query は新しい Digital Link の構築には引き続き認めません。

builder の base path または正規化した prefix 中の raw caret は `%5E` としてシリアライズします。その GTIN に対し、`https://example.com/a^b` は `https://example.com/a%5Eb/01/04912345678904` を構築します。既存の `%5E` escape は二重に符号化せず保持します。userinfo と query の encoding は別のままです。6 件の native regression 検査が、固定した TypeScript `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` に対して、これらの出力と保持の control を対象にします。既存の 1,411 case と 80 restoration/168 residual の corpus 契約は変更しません。

正しい汎用 IDNA/UTS46 実装を提供していないため、raw Unicode host と全角数字の host は引き続き未対応です。必要な場合は、適切な符号化済み ASCII hostname を渡してください。ASCII punycode 名は ASCII 入力として受け付けますが、すべての IDNA 検証・mapping の実装を主張するものではありません。IPv6 zone identifier、不正な IPv6、不正な host delimiter、範囲外の IPv4/port は拒否します。authority 入力の作業量上限は 1,024 文字です。

すべての percent escape を、厳密な scalar UTF-8 として検証します。未知 query フィールドや userinfo でも、不正な escape、過長な sequence、surrogate、範囲外の scalar、途中で切れた sequence、復号した NUL は拒否します。不正な byte を黙って置換しないための意図的な動作です。Godot String も復号した NUL を保持できません。それ以外の未知 query の Unicode は保持します。query の + は space を意味し、出力 query の encoding は大文字の percent hex と form encoding を使います。

AI/value の path segment は dot 正規化の前に調べます。literal または符号化された `.`/`..` の payload path 値は拒否します。literal `%2e` データは `%252e` として往復変換され、query の `.`/`..` はデータのままです。builder は dot-only の qualifier 値を、path に選択していても自動的に query へ配置します。dot cleanup を適用するのは、GS1 ではない base/prefix の path component だけです。解析時の内部の空 segment は拒否し、先頭・末尾の slash は許容します。builder prefix の空 segment は正規化し、整理後の base に literal または符号化された primary-AI component を含めることはできません。

## Validation results and budgets

`validate_gs1_elements`、`validate_gs1_element_string`、`validate_gs1_digital_link` は、`ok`、`errors`、`warnings` と、該当する `elements`/`hasSeparators` または `result` を含む検証レポートを返します。失敗した検証レポートはエラー Dictionary ではないため、`ok` を調べてください。欠けている値は null です。issue の位置は 0 始まりです。

要素の options は `context`（`"element-string"` または `"digital-link"`）、`collectAllErrors`（既定値 true）、`allowUnsupportedAi`（対応する値は false のみ）です。raw の検証でも context を適用します。Digital Link の検証は parse options と `normalize: false` を受け付け、変換には別の normalizer を使います。HTTP と保持した未知 query フィールドは警告を生成します。

変換 helper のエラーは code `INVALID_GS1` と `GS1_*` detailCode を持ちます。検証 issue の code はその詳細理由を含みます。全体の型・資源の失敗は検証を終了し、collectAllErrors=false は最初のフィールドの失敗で停止します。

上限は、UTF-16 相当の入力単位 1,000,000、要素/object field 16,384、要素の AI/value の合計 UTF-8 byte 数 1,000,000 です。astral scalar は入力単位 2 個として数えます。URL component、復号したフィールド、query の合計にも上限があります。Godot のテキスト NUL は未対応ですが、binary encoding は損失なく保持します。

## Compatibility evidence

元の過去入力 1,411 件はすべて変更せず保持します。入力は TypeScript `15ad15e5c770ea0e39072f8f88b2733018f02ffd` に由来します。現行 TypeScript `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` を新たに実行した完全な oracle を、source、harness、runtime の出自とともに `verification/fixtures/current-ts-gs1-1411.json.gz` へ固定しています。

以前に継承した Nim/Perl profile は、その現行参照と 248 件の差があり、そのうち 111 件は参照が受け付ける入力を拒否していました。この版では、受理される入力のうち 77 件と、IPv6 表記 3 件を復元します。`approved-restorations80.json` は、復元した各 case を正確な現行 TypeScript の結果に結び付けます。これらは受理結果を明示的に検証する assertion であり、case の省略やエラー検査の単なる緩和ではありません。

残す **168** 件の差を明示しています。

- **132 件の診断のみの差**: 両実装とも拒否しますが、reason/code の分類が異なります。エラーの文言は互換性の約束ではありません。
- **34 件の受理から拒否への差**: 厳密な malformed-percent/UTF-8/NUL の 20 件、Unicode/IDNA host の 12 件、要求された Digital Link primary-identifier context を適用する raw element-string の検証 2 件です。
- **2 件の安全な受理範囲の拡張**: dot-only の qualifier 値を自動的に query へ配置します。TypeScript では、代わりに呼出側へ `pathAis: []` の指定を求めます。

したがって、現行 TypeScript の契約 1,243 件は直接一致し、他の 168 件は範囲を限定した例外台帳 `native-intentional-deltas168.json` と個別に照合します。期待値は、固定した Nim の動作と、URL 補正後の診断 phase に対する明示的な意味上の witness から独立に導出し、候補の出力からはコピーしません。完全なブラウザー URL 対応や GS1 全体の認証ではありません。

追加の共有 GS1 操作 49 件もすべて維持します。内訳は authority 操作 21 件と dot/data 保持操作 28 件です。以前に authority で拒否した 18 件は、現行 TS の受理結果を期待値にしています。残る共有例外 3 件は、安全な dot builder 2 件と、両実装が拒否する `example.0x` の検証で診断分類だけが異なる 1 件です。shared49 oracle と 3 case の例外台帳は別々に固定しています。102 件の FNC1 encoding regression vector は変更していません。

native tests は以前の authority 入力もすべて保持し、拒否から受理へ移した assertion の対応表を提供します。また、userinfo、符号化された delimiter、IPv4 overflow、port 境界、IPv6 圧縮を含む、独立に生成した現行 TS authority corpus を検査します。完全な gate には `script/verify_gs1.py` と native aggregate を実行してください。以前の Nim/Perl profile の証拠は過去の出自として残し、復元した case の受理 oracle には使いません。
