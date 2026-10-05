extends SceneTree
const GS1 = preload("../addons/specqr/gs1.gd")
const Err = preload("../addons/specqr/error.gd")
var checks = 0
var failures = []
const GTIN = "09506000134352"
const URI = "https://example.com/01/" + GTIN

func _check(ok, label):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: " + label)

func _error(value, code, label):
	_check(Err.is_error(value) and value.code == "INVALID_GS1" and value.get("detailCode") == code, label)

func _init():
	var primary = {"ai": "01", "value": GTIN}
	var catalog = GS1.get_supported_gs1_ais()
	_check(catalog.size() == 50, "50 AIs")
	for info in catalog:
		var value = "X" if info.valueKind == "text" else "1" if info.length.isVariable else "0".repeat(info.length.exact)
		var elements = [{"ai": info.ai, "value": value}]
		_check(GS1.parse_gs1_human_readable(GS1.gs1_to_human_readable(elements)) == elements, "HRI roundtrip AI " + info.ai)
		_check(GS1.parse_gs1_element_string(GS1.create_gs1_element_string(elements)).elements == elements, "raw roundtrip AI " + info.ai)
		_check(GS1.validate_gs1_elements(elements).ok, "validation AI " + info.ai)
	catalog[0].length.exact = 1
	catalog[3].digitalLinkPathForPrimary[0] = "00"
	_check(GS1.get_gs1_ai_info("00").length.exact == 18, "defensive fixed length metadata")
	_check(GS1.get_gs1_ai_info("10").digitalLinkPathForPrimary == ["01"], "defensive nested metadata")
	_check(GS1.calculate_gs1_check_digit("0950600013435") == "2", "check digit")
	_check(GS1.append_gtin_check_digit("0950600013435") == GTIN, "append GTIN")
	_check(GS1.validate_gtin_check_digit(GTIN), "valid GTIN")
	_check(not GS1.validate_gtin_check_digit("09506000134353"), "invalid GTIN check digit")
	for body in ["1234567", "12345678901", "123456789012", "1234567890123"]:
		_check(GS1.validate_gtin_check_digit(GS1.append_gtin_check_digit(body)), "GTIN body length " + str(body.length()))
	_check(GS1.validate_sscc_check_digit(GS1.append_sscc_check_digit("12345678901234567")), "SSCC check digit")
	for bad in [null, 1, 0.5, [], {}, true, PackedByteArray([49])]:
		_error(GS1.calculate_gs1_check_digit(bad), "GS1_INVALID_INPUT", "strict GS1 string " + str(typeof(bad)))
	var elements = [primary, {"ai": "10", "value": "LOT-A"}, {"ai": "17", "value": "271231"}]
	var hri = "(01)" + GTIN + "(10)LOT-A(17)271231"
	var raw = "01" + GTIN + "10LOT-A\u001d17271231"
	for input in [raw, hri, GS1.parse_gs1_element_string(raw), elements]:
		_check(GS1.normalize_gs1_elements(input) == elements, "normalize input " + str(typeof(input)))
	_check(GS1.create_gs1_element_string(elements) == raw, "separator construction")
	_check(GS1.gs1_to_human_readable(elements) == hri, "HRI construction")
	_error(GS1.parse_gs1_element_string("10LOT17271231"), "GS1_MISSING_SEPARATOR", "missing separator")
	for input in ["\u001d10X", "10X\u001d", "17271231\u001d10X", "10X\u001d\u001d21Y"]:
		_error(GS1.parse_gs1_element_string(input), "GS1_UNEXPECTED_SEPARATOR", "unexpected separator")
	var bad = [{"ai": "01", "value": "bad"}, {"ai": "17", "value": "short"}]
	_check(GS1.validate_gs1_elements(bad).errors.size() == 2, "collect all errors")
	_check(GS1.validate_gs1_elements(bad, {"collectAllErrors": false}).errors.size() == 1, "stop on first error")
	for options in [{"allowUnsupportedAi": true}, {"context": "other"}, {"collectAllErrors": "false"}, {"unknown": 0}, {"context": 0}, {"allowUnsupportedAi": "0"}, {"collectAllErrors": 0}, {"collectAllErrors": 1}, {"collectAllErrors": 1.0}, {"isSpecQRError": true, "code": "forged"}]:
		_check(not GS1.validate_gs1_elements([primary], options).ok, "invalid GS1 options")
	_check(not GS1.validate_gs1_elements([{"ai": "10", "value": "x"}], {"context": "digital-link"}).ok, "Digital Link primary required")
	for invalid in [null, 1, {}, [{"ai": 10, "value": "ABC"}], [{"ai": "10", "value": 123}], [[10, "ABC"]], [{"isSpecQRError": true, "code": "forged"}]]:
		_check(not GS1.validate_gs1_elements(invalid).ok, "invalid container and forged error")
	var cycle = []
	cycle.append(cycle)
	_check(not GS1.validate_gs1_elements(cycle).ok, "cycle is rejected without recursion")
	cycle.clear()
	for dot in [".", "..", "%2e", "%2E%2e", ".%2E", "%2e."]:
		var link = URI + "/10/" + dot
		_error(GS1.parse_gs1_digital_link(link), "GS1_INVALID_DIGITAL_LINK_PLACEMENT", "parse dot payload " + dot)
		_error(GS1.normalize_gs1_digital_link(link), "GS1_INVALID_DIGITAL_LINK_PLACEMENT", "normalize dot payload " + dot)
		_check(not GS1.validate_gs1_digital_link(link).ok, "validate dot payload " + dot)
	for data in ["%2e", "%2E%2e", "%", "100%", "%2f", "a/b", "a?b", "a#b", "a+b", "a&b", ".", ".."]:
		var values = [primary, {"ai": "10", "value": data}]
		var link = GS1.create_gs1_digital_link(values)
		_check(GS1.parse_gs1_digital_link(link).elements == values, "literal payload preserved " + data)
		_check(GS1.normalize_gs1_digital_link(link) == link, "normalization idempotent " + data)
	for base in ["https://example.com/a/../b", "https://example.com/a/%2E%2e/b"]:
		_check(GS1.create_gs1_digital_link([primary], {"baseUrl": base}) == "https://example.com/b/01/" + GTIN, "prefix dot canonicalization")
	_error(GS1.create_gs1_digital_link([primary], {"baseUrl": "https://example.com/%30%31"}), "GS1_INVALID_DIGITAL_LINK_PLACEMENT", "encoded base primary rejected")
	_error(GS1.parse_gs1_digital_link("https://example.com/01/./../01/" + GTIN), "GS1_INVALID_DIGITAL_LINK_PLACEMENT", "dot erasure cannot hide payload")
	for bad_percent in ["%", "%0", "%GG", "%C0%AF", "%ED%A0%80", "%F4%90%80%80", "%FF", "%00", "%E2%82", "%F0%80%80%80", "%80"]:
		_error(GS1.parse_gs1_digital_link(URI + "?x=" + bad_percent), "GS1_INVALID_PERCENT_ENCODING", "bad percent or UTF8 " + bad_percent)
	_check(GS1.normalize_gs1_digital_link(URI + "?x=😀") == URI + "?x=%F0%9F%98%80", "Unicode unknown query UTF8")
	var unknown = "https://EXAMPLE.COM:00443/p/01/" + GTIN + "?utm=a&utm=b&x=a+b&empty&x=%E6%97%A5%E6%9C%AC&17=271231"
	var normalized = "https://example.com/p/01/" + GTIN + "?17=271231&utm=a&utm=b&x=a+b&empty=&x=%E6%97%A5%E6%9C%AC"
	_check(GS1.normalize_gs1_digital_link(unknown) == normalized, "safe repeated unknown query preservation")
	_check(GS1.normalize_gs1_digital_link(normalized) == normalized, "unknown query normalization idempotent")
	_check(GS1.validate_gs1_digital_link(unknown).warnings[0].count == 5, "unknown query warning count")
	_error(GS1.parse_gs1_digital_link(unknown, {"unknownQuery": "reject"}), "GS1_DIGITAL_LINK_UNKNOWN_QUERY", "unknown query rejection policy")
	for host in ["example.com", "EXAMPLE.COM", "example.com.", "xn--bcher-kva.example", "localhost", "127.0.0.1", "192.168.1.1", "8.8.8.8", "0.0.0.0", "[::1]", "[2001:db8::1]", "[::ffff:192.0.2.1]", "[1:2:3:4:5:6:7:8]"]:
		_check(GS1.parse_gs1_digital_link("https://" + host + "/01/" + GTIN).primary == primary, "supported host " + host)
	for host in ["example.0x", "1.2.3.256", "example.123", "example.0xff", "例.jp", "[::1%25eth0]", "[1:2:3:4:5:6:7]", "[1:2:3:4:5:6:7:8:9]", "[:::]", "[1::2::3]", "[::ffff:192.000.2.1]", "[1.2.3.4::]", "[::1]oops"]:
		_error(GS1.parse_gs1_digital_link("https://" + host + "/01/" + GTIN), "GS1_DIGITAL_LINK_UNSUPPORTED_HOST", "rejected host " + host)
	_error(GS1.parse_gs1_digital_link("https://"), "GS1_DIGITAL_LINK_UNSUPPORTED_HOST", "empty authority rejected")
	for port in ["-1", "+443", "65536", "123456", "a", "443:80"]:
		_error(GS1.parse_gs1_digital_link("https://example.com:" + port + "/01/" + GTIN), "GS1_DIGITAL_LINK_INVALID_URI", "rejected port " + port)
	for link in ["ftp://example.com/01/" + GTIN, "//example.com/01/" + GTIN, "HTTPſ://example.com/01/" + GTIN]:
		_error(GS1.parse_gs1_digital_link(link), "GS1_DIGITAL_LINK_INVALID_URI", "rejected URI")
	_error(GS1.calculate_gs1_check_digit("1".repeat(GS1.GS1_MAX_INPUT_CHARACTERS + 1)), "GS1_INVALID_INPUT", "input budget")
	var excess = []
	excess.resize(GS1.GS1_MAX_ELEMENTS + 1)
	excess.fill({"ai": "10", "value": "X"})
	_error(GS1.create_gs1_element_string(excess), "GS1_INVALID_INPUT", "element budget")
	_error(GS1.normalize_gs1_elements([{"ai": "10", "value": "A".repeat(GS1.GS1_MAX_INPUT_CHARACTERS)}]), "GS1_INVALID_INPUT", "aggregate text budget")
	_error(GS1.parse_gs1_digital_link(URI + "?" + "x=y&".repeat(GS1.GS1_MAX_ELEMENTS)), "GS1_INVALID_INPUT", "URL component budget")
	print(JSON.stringify({"checks": checks, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
