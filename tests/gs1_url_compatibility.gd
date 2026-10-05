extends SceneTree
const GS1 = preload("../addons/specqr/gs1.gd")
const Err = preload("../addons/specqr/error.gd")
const GTIN = "04912345678904"
const URI = "https://example.com/01/" + GTIN
var checks = 0
var failures = []

func _check(condition, label):
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: " + label)

func _init():
	var expected = GS1.parse_gs1_digital_link(URI)
	for input in [URI + "#", "https:example.com/01/" + GTIN, "https:/example.com/01/" + GTIN, "https:////example.com/01/" + GTIN, "https:\\example.com\\01\\" + GTIN, " \t\r\n" + URI + " \r\n", "ht\ttps://exam\nple.com/01/" + GTIN]:
		_check(GS1.parse_gs1_digital_link(input) == expected, "accepted URL lexical form " + input)
		_check(GS1.normalize_gs1_digital_link(input) == URI, "normalized URL lexical form " + input)
		_check(GS1.validate_gs1_digital_link(input).ok, "validated URL lexical form " + input)
	var elements = [{"ai": "01", "value": GTIN}, {"ai": "10", "value": "ABC123"}, {"ai": "17", "value": "251231"}]
	var built = URI + "/10/ABC123?17=251231"
	_check(GS1.create_gs1_digital_link(elements, {"baseUrl": "https://example.com?"}) == built, "empty base query discarded")
	_check(GS1.create_gs1_digital_link(elements, {"baseUrl": "https://example.com#"}) == built + "#", "empty base fragment preserved")
	_check(GS1.create_gs1_digital_link(elements, {"baseUrl": "https://example.com?#"}) == built + "#", "both empty base delimiters")
	_check(Err.is_error(GS1.create_gs1_digital_link(elements, {"baseUrl": "https://example.com?x=1"})), "nonempty base query rejected")
	_check(Err.is_error(GS1.create_gs1_digital_link(elements, {"baseUrl": "https://example.com#x"})), "nonempty base fragment rejected")
	var query = URI + "?foo=a\\tb&foo=x/y&x=a+b&x=a%2Bb&empty&tab=a\tb"
	var parsed = GS1.parse_gs1_digital_link(query)
	_check(not Err.is_error(parsed) and parsed.unknownQuery == [{"key": "foo", "value": "a\\tb"}, {"key": "foo", "value": "x/y"}, {"key": "x", "value": "a b"}, {"key": "x", "value": "a+b"}, {"key": "empty", "value": ""}, {"key": "tab", "value": "ab"}], "query backslashes and duplicates preserved; literal tab removed")
	_check(GS1.normalize_gs1_digital_link(query) == URI + "?foo=a%5Ctb&foo=x%2Fy&x=a+b&x=a%2Bb&empty=&tab=ab", "query safe canonicalization")
	_check(GS1.normalize_gs1_digital_link(URI + "?foo=raw space") == URI + "?foo=raw+space", "raw query space preserved")
	_check(GS1.parse_gs1_digital_link(URI + "/10/A B").elements[1].value == "A B", "raw path space preserved")
	_check(GS1.create_gs1_digital_link(elements, {"baseUrl": "https://example.com/a b"}) == "https://example.com/a%20b/01/" + GTIN + "/10/ABC123?17=251231", "base path space encoded")
	for dot in [".", "..", "%2e", "%2E%2e", ".%2E", "%2e."]:
		for prefix in [URI + "/10/", "https:example.com/01/" + GTIN + "/10/", " https:\\example.com\\01\\" + GTIN + "\\10\\"]:
			var value = GS1.parse_gs1_digital_link(prefix + dot)
			_check(Err.is_error(value) and value.detailCode == "GS1_INVALID_DIGITAL_LINK_PLACEMENT", "payload dot rejection after repairs")
	for suffix in ["%", "%GG", "%C0%AF", "%ED%A0%80", "%F4%90%80%80", "%00"]:
		var value = GS1.parse_gs1_digital_link(URI + "?x=" + suffix)
		_check(Err.is_error(value) and value.detailCode == "GS1_INVALID_PERCENT_ENCODING", "strict percent UTF8 NUL rejection " + suffix)
	for input in [URI + "#x", URI + "##", "//example.com/01/" + GTIN, "ftp://example.com/01/" + GTIN]:
		_check(Err.is_error(GS1.parse_gs1_digital_link(input)), "still invalid URL " + input)
	var authority_fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/gs1_authority_expected.json"))
	for test in authority_fixtures.cases:
		var actual = GS1.normalize_gs1_digital_link(test.input)
		if typeof(test.expected) == TYPE_DICTIONARY:
			_check(Err.is_error(actual) and actual.code == test.expected.throws.code, "authority rejection matches current TypeScript")
		else:
			_check(actual == test.expected, "authority normalization matches current TypeScript")
			_check(GS1.validate_gs1_digital_link(test.input).ok, "authority parse accepted by current TypeScript")
			_check(GS1.normalize_gs1_digital_link(actual) == actual, "authority normalization idempotent")
	for host in ["é.com", "例え.テスト", "１２７.１", "%C3%A9.com"]:
		var actual = GS1.normalize_gs1_digital_link("https://" + host + "/01/" + GTIN)
		_check(Err.is_error(actual) and actual.detailCode == "GS1_DIGITAL_LINK_UNSUPPORTED_HOST", "explicit Unicode/IDNA limitation")
	for credentials in ["user%GG:pass", "user:pass%00", "user%C0%AF:pass", "user:pass%ED%A0%80"]:
		var actual = GS1.normalize_gs1_digital_link("https://" + credentials + "@example.com/01/" + GTIN)
		_check(Err.is_error(actual) and actual.detailCode == "GS1_INVALID_PERCENT_ENCODING", "strict credential percent UTF8 NUL validation")
	print(JSON.stringify({"checks": checks, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
