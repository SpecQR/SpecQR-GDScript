# Independent GS1 verification

The library requires only standard Godot.

パッケージ検証では、固定した合成 fixture を Python で読み、実際の GDScript 実装を実行します。Node.js と Nim は任意の出自確認ツールであり、encoder の依存関係にはなりません。

## Authoritative current-source cases

`fixtures/gs1-upstream.json` は変更せず、元の 1,411 request をすべて残します。`fixtures/current-ts-gs1-1411.json.gz` は、各 request と、新たに実行した現行 TypeScript の結果を、case ID、request hash、source-tree/source-file hash、oracle harness hash、toolchain version、出力 digest とともに含みます。ここでの path は `verification/` からの相対 path です。

固定する source:

- 過去の request: TypeScript `15ad15e5c770ea0e39072f8f88b2733018f02ffd`
- 現行 TypeScript: https://github.com/SpecQR/SpecQR の
  `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7`、Node.js v24.19.0
- 独立した native witness: https://github.com/SpecQR/SpecQR-Nim の
  `4f9154664d35a24cecb30b75cfdba0a9f16ced3e`、Nim 2.2.12 C backend。
  `src/specqr/gs1.nim` SHA256
  `9df6a11927f265108e4d01e3321a208e1bcd4f9c484ff6aad5f9b8bd42734fa3`

## Explicit compatibility accounting

現行 verifier は、1,243 件の正確な public 契約が現行 TypeScript と一致することを要求します。復元した 80 case も、それぞれ別の gate で確認します。内訳は、以前に拒否した受理可能な入力 77 件と、IPv6 の canonical 表記結果 3 件です。request に結び付いた完全な対象は `fixtures/approved-restorations80.json` にあります。

正確に 168 件の residual 差を、`fixtures/native-intentional-deltas168.json` に明示して残します。

- 132 件の診断 code/reason/count の規約
- 34 件の受理から拒否への差: 厳密な percent/UTF-8/NUL の 20 件、IDNA host の 12 件、raw Digital Link context-primary の 2 件
- dot-only の GS1 payload 値を保持する、安全な dot-query の 2 件

URL 正規化が受理され、後段の validator に到達するようになったため、診断値 5 件が変わります。`fixtures/diagnostic-migrations5.json` は、元の各 request と以前の値を、新たに実行した独立 Nim の意味上の witness、その結果、検証順序の理由に結び付けます。受理結果や residual case ID は変更しません。候補 GDScript の出力から期待値を生成することはありません。

比較では、正規化した public field が双方向で正確に一致することを要求します。言語間の正規化は、省略可能な null、`length.isVariable`、成功時の空の `errors`、英語の診断文言、補助的な診断 field を除去し、すべての payload/catalog field と、診断 code・reason・count を保持します。native tests は、言語固有の完全な metadata と所有権を別途対象にします。

## Existing shared vectors remain active

`fixtures/current-ts-gs1-shared49.json` は、変更していない strict-authority と共有 Digital Link fixture から全 49 操作を独立に評価します。有効な alias host 全 6 件は、TypeScript の受理結果 18 件を明示します。`example.0x` は、不正入力の拒否 control 3 件として残します。

`fixtures/native-shared-gs1-deltas3.json` が結び付ける意図的な例外は、安全な dot builder 2 件と `example.0x` の検証診断の、3 件だけです。既存の Digital Link 保持操作 28 件も、すべて引き続き検査します。最終的な対象結果は受理 25 操作、拒否 24 操作です。省略するものはありません。

以前の `fixtures/gs1-profile-deltas.json` は、前の限定 profile の出自として残します（過去の差 252 件、当時の現行 TS に対して 248 件）。現在の期待値の source ではありません。そこから継承した広い範囲制限を、現在の成功として主張しません。

## Optional regeneration

独立に検証した、正確な固定 source のローカル checkout を指定してください。

```sh
nim c --path:/path/to/SpecQR-Nim/src \
  --nimcache:/tmp/specqr-gs1-oracle-cache \
  -o:/tmp/specqr-gs1-oracle verification/gs1/nim_oracle.nim
/tmp/specqr-gs1-oracle verification/fixtures/gs1-upstream.json > /tmp/gs1-nim.json
node verification/gs1/current_ts_oracle.mjs /path/to/SpecQR \
  verification/fixtures/gs1-upstream.json > /tmp/gs1-current-ts.json
SPECQR_GODOT=/path/to/godot python3 script/verify_gs1.py \
  --binary script/bridge.gd --output /tmp/gs1-gdscript.json
```

リポジトリ内の生成 harness は、候補 GDScript コードも候補出力も import しません。必要な fixture と request の hash はすべて `script/gs1_contract.py` が検査します。テスト対象の各 engine で、全 1,411 request を実行します。
