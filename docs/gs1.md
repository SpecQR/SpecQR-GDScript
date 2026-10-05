# GS1 and GS1 Digital Link

The native GDScript GS1 module implements SpecQR's bounded 50-AI catalog. It performs no network access, DNS lookup, subprocess execution or host URL repair. All helpers are available through the public `SpecQR` facade.

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

Check `QR.is_error` after each transforming operation. AIs and values are actual Strings: quote numeric values to preserve leading zeroes. Elements are Arrays of Dictionaries; options are Dictionaries with camelCase String/StringName keys and strict boolean values. StringName keys, including dot-created keys, are normalized to owned String keys; other key types are rejected. Values remain strict Strings/booleans as specified. Unknown option names are rejected. The returned catalog, metadata and normalized elements are owned copies.

## Catalog

`get_supported_gs1_ais()` returns 50 records. `get_gs1_ai_info(ai)` returns metadata or null for an unsupported AI. Fields are `ai`, `label`, `length`, `valueKind`, `checkDigitRule`, `digitalLinkRole`, `separator`, `digitalLinkPathForPrimary`.

Supported AIs: 00, 01, 02, 10, 11, 12, 13, 15, 16, 17, 20, 21, 22, 30, 37, 240, 241, 400, 410–415, 420, 422, 424, 425, 426, 3100–3105, 3200–3205, 91–99.

Validation checks fixed/variable lengths, numeric or printable ASCII values, relevant GTIN/SSCC check digits, raw parentheses and separators. Element values are printable ASCII. A percent is literal data at this layer; FNC1 conversion is handled by the encoder.

This is not comprehensive GS1 certification. Date fields require six digits, not a valid calendar date. GLNs 410–415 require 13 digits but do not validate their check digits. Unsupported AIs are rejected; the module does not enforce every GS1 AI combination rule.

## Element strings and check digits

- `normalize_gs1_elements(input)` accepts an element Array, `{elements: [...]}`, raw String or parenthesized HRI String
- `parse_gs1_human_readable(text)` → element Array
- `parse_gs1_element_string(text)` → `{elements,hasSeparators}`
- `create_gs1_element_string(elements)` inserts U+001D after nonfinal variable fields
- `gs1_to_human_readable(elements)`, `gs1_element_string_to_human_readable(raw)`
- Aliases: `gs1_normalize`, `gs1_from_human_readable`, `gs1_to_element_string`, `gs1_build`, `gs1_parse`
- `calculate_gs1_check_digit`, `validate_gs1_check_digit`
- `calculate_gtin_check_digit`, `append_gtin_check_digit`, `validate_gtin_check_digit`
- `calculate_sscc_check_digit`, `append_sscc_check_digit`, `validate_sscc_check_digit`

GTIN bodies contain 7, 11, 12 or 13 digits; SSCC bodies contain 17. Calculation accepts the body, validation the completed number. A correctly shaped number with a wrong check digit returns false; malformed input returns an error. Modulo-10 weights alternate 3,1 from right to left.

The raw parser uses SpecQR's conservative ambiguity check: an apparent complete fixed-length AI suffix in an unseparated final variable value is rejected as a missing separator, even if the supposed suffix data would fail numeric validation. Some printable terminal lot values can therefore be rejected. Use structured element Arrays or HRI when generating such values.

## Digital Link helpers

`create_gs1_digital_link(elements, options=null)` supports:

- `baseUrl`: default https://id.gs1.org
- `primaryAi`: default `"01"`; `"00"` and `"414"` also supported
- `pathAis`: selected qualifiers; an explicit empty Array puts qualifiers in query
- `explicitPathAis`: bool; true honors explicit selection even without pathAis

Primary 01 qualifiers 10,21,22 enter the path by default. Path order follows input order; remaining known query data is sorted by AI then value. Duplicate AIs or invalid path choices are rejected. Dot-only qualifier values are placed in query even if requested in path. Aliases: `gs1_digital_link`, `gs1_to_digital_link`.

`parse_gs1_digital_link(uri, options=null)` returns `elements`, `primary`, `pathElements`, `queryElements`, `unknownQuery`. Options: `primaryAi` (otherwise discover the first literal 00/01/414 path segment) and `unknownQuery` (`"preserve"`, default, or `"reject"`). An encoded primary-AI segment is not used for discovery. Numeric 2–4-digit query keys are treated as AIs and must be supported. Unknown query duplicates and order are retained.

`normalize_gs1_digital_link(uri, options=null)` adds `mode: "specqr-deterministic"`, the only mode. It rebuilds known fields deterministically, selects default eligible path qualifiers, sorts known queries and appends preserved unknown pairs in original order. It is idempotent in the documented profile and uses deterministic IPv6 serialization. Unicode host IDNA/UTS46 remains outside the implemented profile.

## Offline HTTP(S) normalization and explicit limits

The implementation handles the common ASCII HTTP(S) URL normalization used by the pinned TypeScript baseline. It is still a bounded offline parser, not a complete WHATWG/UTS46 implementation, an SSRF defense or a reachability check. It performs no DNS or network operations. Localhost, private addresses and loopback are accepted syntax.

Supported normalization includes:

- ASCII URL host/reg-name case folding, including underscores and other browser-accepted non-DNS labels
- Strictly decoded ASCII percent-encoded hosts; encoded host delimiters and malformed escapes are rejected
- Decimal, octal and hexadecimal IPv4 forms, one-to-four components and a final dot, with checked 32-bit arithmetic; output is canonical dotted decimal
- Bracketed IPv6, longest zero-run compression with first-run tie breaking, lowercase hex and conversion of dotted IPv4 tails to hex groups
- Decimal ports 0..65535, including leading zeroes or an empty port; HTTP/HTTPS defaults are omitted
- Rightmost-@ userinfo parsing and URL-style user/password encoding, preserving existing escapes and credential bytes in the requested URI output
- Leading/trailing ASCII control/space trimming, TAB/CR/LF removal, incomplete/excess-slash HTTP(S) syntax and authority/path backslash repair

A backslash in query data remains data and is encoded during normalization. No relative URL base is assumed: non-HTTP(S) schemes and scheme-free input are rejected. Nonempty fragments are rejected. Empty fragments are accepted; a builder preserves an empty base fragment marker for TypeScript compatibility, while normalization removes it. An empty base query is accepted; nonempty base queries remain disallowed for building a new Digital Link.

Raw Unicode hosts and fullwidth-number hosts remain unsupported because a correct general IDNA/UTS46 implementation is not provided. Pass a suitable already-encoded ASCII hostname when needed. ASCII punycode names are accepted as ASCII input; this is not a claim to implement all IDNA validation/mapping. IPv6 zone identifiers, malformed IPv6, invalid host delimiters and out-of-range IPv4/ports are rejected. Authority input has a 1,024-character work budget.

Every percent escape is validated as strict scalar UTF-8. Malformed escapes, overlong sequences, surrogates, out-of-range scalars, truncated sequences and decoded NUL are rejected, even in unknown query fields or userinfo. This deliberately avoids silently replacing invalid bytes. Godot String also cannot preserve decoded NUL. Unknown query Unicode is otherwise preserved; query + means space, and output query encoding uses uppercase percent hex and form encoding.

AI/value path segments are examined before dot normalization. Literal or encoded `.`/`..` payload path values are rejected. Literal `%2e` data round-trips as `%252e`; query `.`/`..` remain data. The builder automatically places dot-only qualifier values in query, even if selected for path. Only non-GS1 base/prefix path components receive dot cleanup. Empty internal parsing segments are rejected; leading/trailing slashes are tolerated. Builder prefix empty segments are normalized, and a cleaned base cannot contain literal or encoded primary-AI components.

## Validation results and budgets

`validate_gs1_elements`, `validate_gs1_element_string`, `validate_gs1_digital_link` return validation reports with `ok`, `errors`, `warnings`, and relevant `elements`/`hasSeparators` or `result`. A failed validation report is not an error Dictionary: examine `ok`. Missing values are null. Issue locations are zero-based.

Element options: `context` (`"element-string"` or `"digital-link"`), `collectAllErrors` (default true), `allowUnsupportedAi` (false is the only supported value). Raw validation enforces context too. Digital Link validation accepts parse options and `normalize: false`; use the separate normalizer for transformations. HTTP and preserved unknown-query fields create warnings.

Transforming helper errors have code `INVALID_GS1` and a `GS1_*` detailCode. Validation issue code contains that detailed reason. Global type/resource failures terminate validation; collectAllErrors=false stops on the first field failure.

Budgets: 1,000,000 UTF-16-equivalent input units, 16,384 elements/object fields, and 1,000,000 aggregate element AI/value UTF-8 bytes. Astral scalars count as two input units. URL components, decoded fields and query aggregates are also bounded. Godot text NUL is unsupported; binary encoding remains lossless.

## Compatibility evidence

All 1,411 original historical inputs are retained unchanged. They originate at TypeScript `15ad15e5c770ea0e39072f8f88b2733018f02ffd`. A complete fresh oracle from current TypeScript `16efc6c0a8e397c9df3d051d20fce6c1eebdfad7` is pinned in `verification/fixtures/current-ts-gs1-1411.json.gz` with source, harness and runtime provenance.

The former inherited Nim/Perl profile had 248 differences from that current reference, including 111 accepted inputs it rejected. This edition restores 77 of those accepted-input cases and three IPv6 spelling cases. `approved-restorations80.json` binds every restored case to the exact current-TypeScript outcome. These are positive assertions, not skipped cases or merely relaxed error checking.

The selected remaining **168** differences are explicit:

- **132 diagnostic-only** differences: both implementations reject, but reason/code categorization differs. Error wording is not a compatibility promise.
- **34 accepted-to-rejected** differences: 20 strict malformed-percent/UTF-8/NUL cases, 12 Unicode/IDNA host cases, and two raw element-string validations that enforce the requested Digital Link primary-identifier context.
- **2 safe broader acceptances**: dot-only qualifier values are placed in query automatically; TypeScript instead asks the caller to specify `pathAis: []`.

Thus 1,243 current-TypeScript contracts agree directly, and the other 168 are checked individually against a bounded exception ledger, `native-intentional-deltas168.json`. Its expectations are independently derived from pinned Nim behavior and explicit semantic witnesses for diagnostic phases after URL repair, never copied from the candidate's output. This is not full browser URL or comprehensive GS1 certification.

All 49 additional shared GS1 operations also remain: 21 authority operations and 28 dot/data-preservation operations. Eighteen old authority rejections now have positive current-TS expectations. The three remaining shared exceptions are the two safe dot builders and one diagnostic-only validation category for `example.0x`, which both implementations reject. The shared49 oracle and three-case exception ledger are pinned separately. The 102 FNC1 encoding regression vectors are unchanged.

Native tests additionally retain every previous authority input, provide a mapping for assertions moved from negative to positive, and check an independently generated current-TS authority corpus including userinfo, encoded delimiters, IPv4 overflow, port boundaries and IPv6 compression. Run `script/verify_gs1.py` and the native aggregate for the complete gates. Earlier Nim/Perl profile evidence remains historical provenance, not the acceptance oracle for restored cases.
