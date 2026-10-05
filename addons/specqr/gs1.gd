extends RefCounted
## GS1 application identifiers, element strings and deterministic Digital Links.
## Every failing operation returns a SpecQRError dictionary; validators return issues.
const Err = preload("error.gd")
const GS1_FNC1_SEPARATOR = "\u001d"
const GS1_MAX_INPUT_CHARACTERS = 1000000
const GS1_MAX_ELEMENTS = 16384

static func _fail(message, detail = "GS1_INVALID_INPUT"):
	var out = Err.error("INVALID_GS1", message)
	out["detailCode"] = detail
	return out

static func _text(value, label = "GS1 text"):
	if typeof(value) != TYPE_STRING:
		return _fail(label + " must be a string to preserve leading zeroes")
	if value.length() > GS1_MAX_INPUT_CHARACTERS or value.to_utf8_buffer().size() > 4 * GS1_MAX_INPUT_CHARACTERS:
		return _fail(label + " exceeds the character work budget")
	var units = value.length()
	for i in range(value.length()):
		var cp = value.unicode_at(i)
		if cp < 0 or cp > 0x10ffff or (cp >= 0xd800 and cp <= 0xdfff):
			return _fail(label + " must contain only Unicode scalar values")
		if cp > 0xffff:
			units += 1
			if units > GS1_MAX_INPUT_CHARACTERS:
				return _fail(label + " exceeds the character work budget")
	return value

static func _array(value, label):
	if typeof(value) != TYPE_ARRAY:
		return _fail(label + " must be an array")
	if value.size() > GS1_MAX_ELEMENTS:
		return _fail("GS1 element count exceeds limit")
	return value

static func _hash(value, label):
	if typeof(value) != TYPE_DICTIONARY:
		return _fail(label + " must be a dictionary")
	if value.size() > GS1_MAX_ELEMENTS:
		return _fail(label + " exceeds the field count budget")
	return true

static func _options(input, allowed):
	if input == null:
		return {}
	var checked = _hash(input, "GS1 options")
	if Err.is_error(checked):
		return checked
	var options = {}
	for key in input:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return _fail("GS1 option keys must be String or StringName")
		if key.length() > 64:
			return _fail("Unknown GS1 option")
		var name = String(key)
		if not allowed.has(name):
			return _fail("Unknown GS1 option " + name)
		if options.has(name):
			return _fail("Duplicate normalized GS1 option")
		options[name] = input[key]
	return options

static func _boolean(value, label):
	if typeof(value) == TYPE_BOOL:
		return value
	return _fail(label + " must be boolean")

static func _digits(value):
	if typeof(value) != TYPE_STRING or value.is_empty():
		return false
	for i in range(value.length()):
		if value.unicode_at(i) < 48 or value.unicode_at(i) > 57:
			return false
	return true

static func _is_ai(value):
	return typeof(value) == TYPE_STRING and value.length() >= 2 and value.length() <= 4 and _digits(value)

static func _primary(ai):
	return ai == "00" or ai == "01" or ai == "414"

static func _eligible(ai, primary):
	return primary == "01" and (ai == "10" or ai == "21" or ai == "22")

static func _add(catalog, ai, label, n, variable = false, kind = "numeric", check = "none", role = "data-attribute"):
	catalog[ai] = {"ai": ai, "label": label,
		"length": {"type": "variable", "min": 1, "max": n, "isVariable": true} if variable else {"type": "fixed", "exact": n, "isVariable": false},
		"valueKind": kind, "checkDigitRule": check, "digitalLinkRole": role,
		"separator": "required-when-followed" if variable else "none",
		"digitalLinkPathForPrimary": ["01"] if role == "key-qualifier" else null}

static func _catalog():
	var out = {}
	_add(out, "00", "Serial shipping container code", 18, false, "numeric", "sscc", "primary-key")
	_add(out, "01", "Global trade item number", 14, false, "numeric", "gtin", "primary-key")
	_add(out, "02", "Contained trade item GTIN", 14, false, "numeric", "gtin")
	_add(out, "10", "Batch or lot number", 20, true, "text", "none", "key-qualifier")
	for p in [["11", "Production date"], ["12", "Due date"], ["13", "Packaging date"], ["15", "Best before date"], ["16", "Sell by date"], ["17", "Expiration date"]]:
		_add(out, p[0], p[1], 6)
	_add(out, "20", "Internal product variant", 2)
	_add(out, "21", "Serial number", 20, true, "text", "none", "key-qualifier")
	_add(out, "22", "Consumer product variant", 20, true, "text", "none", "key-qualifier")
	_add(out, "30", "Variable count", 8, true)
	_add(out, "37", "Count of contained trade items", 8, true)
	for p in [["240", "Additional product identification"], ["241", "Customer part number"], ["400", "Customer purchase order number"]]:
		_add(out, p[0], p[1], 30, true, "text")
	for p in [["410", "Ship to global location number"], ["411", "Bill to global location number"], ["412", "Purchased from global location number"], ["413", "Ship for global location number"], ["414", "Identification of a physical location"], ["415", "Global location number of the invoicing party"]]:
		_add(out, p[0], p[1], 13, false, "numeric", "none", "primary-key" if p[0] == "414" else "data-attribute")
	_add(out, "420", "Ship to postal code", 20, true, "text")
	for p in [["422", "Country of origin"], ["424", "Country of processing"], ["425", "Country of disassembly"], ["426", "Country covering full process chain"]]:
		_add(out, p[0], p[1], 3)
	for p in [[3100, "Net weight in kilograms"], [3200, "Net weight in pounds"]]:
		for ai in range(p[0], p[0] + 6):
			_add(out, str(ai), p[1], 6)
	for ai in range(91, 100):
		_add(out, str(ai), "Company internal information", 90, true, "text")
	return out

static func get_supported_gs1_ais():
	return _catalog().values()

static func get_gs1_ai_info(input):
	var ai = _text(input, "GS1 AI")
	if Err.is_error(ai):
		return ai
	return _catalog().get(ai)

static func _numeric(value, label):
	var checked = _text(value, label)
	if Err.is_error(checked):
		return checked
	if not _digits(value):
		return _fail(label + " must contain digits only", "GS1_INVALID_CHARSET")
	return value

static func calculate_gs1_check_digit(input):
	var value = _numeric(input, "GS1 check digit input")
	if Err.is_error(value):
		return value
	var total = 0
	var weight = 3
	for i in range(value.length() - 1, -1, -1):
		total = (total + (value.unicode_at(i) - 48) * weight) % 10
		weight = 4 - weight
	return str((10 - total) % 10)

static func validate_gs1_check_digit(input):
	var value = _numeric(input, "GS1 check digit value")
	if Err.is_error(value):
		return value
	if value.length() < 2:
		return _fail("GS1 check digit value must include body and check digit", "GS1_INVALID_LENGTH")
	return calculate_gs1_check_digit(value.left(-1)) == value.right(1)

static func calculate_gtin_check_digit(input):
	var value = _numeric(input, "GTIN body")
	if Err.is_error(value):
		return value
	if not [7, 11, 12, 13].has(value.length()):
		return _fail("GTIN body must be 7, 11, 12, or 13 digits", "GS1_INVALID_LENGTH")
	return calculate_gs1_check_digit(value)

static func append_gtin_check_digit(input):
	var digit = calculate_gtin_check_digit(input)
	return digit if Err.is_error(digit) else input + digit

static func validate_gtin_check_digit(input):
	var value = _numeric(input, "GTIN")
	if Err.is_error(value):
		return value
	if not [8, 12, 13, 14].has(value.length()):
		return _fail("GTIN must be 8, 12, 13, or 14 digits", "GS1_INVALID_LENGTH")
	return validate_gs1_check_digit(value)

static func calculate_sscc_check_digit(input):
	var value = _numeric(input, "SSCC body")
	if Err.is_error(value):
		return value
	if value.length() != 17:
		return _fail("SSCC body must be exactly 17 digits", "GS1_INVALID_LENGTH")
	return calculate_gs1_check_digit(value)

static func append_sscc_check_digit(input):
	var digit = calculate_sscc_check_digit(input)
	return digit if Err.is_error(digit) else input + digit

static func validate_sscc_check_digit(input):
	var value = _numeric(input, "SSCC")
	if Err.is_error(value):
		return value
	if value.length() != 18:
		return _fail("SSCC must be exactly 18 digits", "GS1_INVALID_LENGTH")
	return validate_gs1_check_digit(value)

static func _bounded_elements(elements):
	var checked = _array(elements, "GS1 elements")
	if Err.is_error(checked):
		return checked
	var work = 0
	for e in elements:
		checked = _hash(e, "GS1 element")
		if Err.is_error(checked):
			return checked
		for field in ["ai", "value"]:
			checked = _text(e.get(field), "GS1 element " + field)
			if Err.is_error(checked):
				return checked
			work += checked.to_utf8_buffer().size()
			if work > GS1_MAX_INPUT_CHARACTERS:
				return _fail("GS1 aggregate text exceeds input budget")
	return true

static func _element(element, index = 0, catalog = null):
	var checked = _hash(element, "GS1 element " + str(index))
	if Err.is_error(checked):
		return checked
	var ai = _text(element.get("ai"), "GS1 element %d AI" % index)
	if Err.is_error(ai):
		return ai
	var value = _text(element.get("value"), "GS1 element %d value" % index)
	if Err.is_error(value):
		return value
	if not _is_ai(ai):
		return _fail("GS1 element %d AI must be a 2 to 4 digit string" % index)
	if catalog == null:
		catalog = _catalog()
	var info = catalog.get(ai)
	if info == null:
		return _fail("Unsupported GS1 AI " + ai, "GS1_UNSUPPORTED_AI")
	var prefix = "GS1 AI " + ai + " value"
	if value.is_empty():
		return _fail(prefix + " must not be empty", "GS1_INVALID_LENGTH")
	if value.contains(GS1_FNC1_SEPARATOR):
		return _fail(prefix + " must not contain the FNC1 separator", "GS1_UNEXPECTED_SEPARATOR")
	if value.contains("(") or value.contains(")"):
		return _fail(prefix + " must be raw data without human-readable parentheses")
	for i in range(value.length()):
		if value.unicode_at(i) < 32 or value.unicode_at(i) > 126:
			return _fail(prefix + " must use printable ASCII characters", "GS1_INVALID_CHARSET")
	if info.valueKind == "numeric" and not _digits(value):
		return _fail(prefix + " must contain digits only", "GS1_INVALID_CHARSET")
	if info.length.isVariable:
		if value.length() > info.length.max:
			return _fail(prefix + " must be at most %d characters" % info.length.max, "GS1_INVALID_LENGTH")
	elif value.length() != info.length.exact:
		return _fail(prefix + " must be exactly %d characters" % info.length.exact, "GS1_INVALID_LENGTH")
	if info.checkDigitRule == "gtin" and not validate_gtin_check_digit(value):
		return _fail(prefix + " has an invalid GTIN check digit", "GS1_INVALID_CHECK_DIGIT")
	if info.checkDigitRule == "sscc" and not validate_sscc_check_digit(value):
		return _fail(prefix + " has an invalid SSCC check digit", "GS1_INVALID_CHECK_DIGIT")
	return {"ai": ai, "value": value}

static func normalize_gs1_elements(input):
	if typeof(input) == TYPE_STRING:
		var checked = _text(input)
		if Err.is_error(checked):
			return checked
		if input.begins_with("("):
			return parse_gs1_human_readable(input)
		var parsed = parse_gs1_element_string(input)
		return parsed if Err.is_error(parsed) else parsed.elements
	if typeof(input) == TYPE_DICTIONARY:
		var checked = _hash(input, "GS1 parse result")
		if Err.is_error(checked):
			return checked
		input = input.get("elements")
	var bounded = _bounded_elements(input)
	if Err.is_error(bounded):
		return bounded
	if input.is_empty():
		return _fail("GS1 elements must not be empty")
	var out = []
	var catalog = _catalog()
	for i in range(input.size()):
		var element = _element(input[i], i, catalog)
		if Err.is_error(element):
			return element
		out.append(element)
	return out

static func _ascii_input(input, label):
	var value = _text(input, label)
	if Err.is_error(value):
		return value
	for i in range(value.length()):
		if value.unicode_at(i) > 127:
			return _fail(label + " must use ASCII characters", "GS1_INVALID_CHARSET")
	if value.is_empty():
		return _fail(label + " must not be empty")
	return value

static func parse_gs1_human_readable(input):
	var value = _ascii_input(input, "GS1 human-readable input")
	if Err.is_error(value):
		return value
	var out = []
	var pos = 0
	var catalog = _catalog()
	while pos < value.length():
		if value.substr(pos, 1) != "(":
			return _fail("GS1 AI must be parenthesized at offset %d" % pos)
		var end = value.find(")", pos + 1)
		if end < 0:
			return _fail("GS1 AI is missing closing parenthesis at offset %d" % pos)
		var stop = value.find("(", end + 1)
		if stop < 0:
			stop = value.length()
		var e = _element({"ai": value.substr(pos + 1, end - pos - 1), "value": value.substr(end + 1, stop - end - 1)}, out.size(), catalog)
		if Err.is_error(e):
			return e
		if out.size() >= GS1_MAX_ELEMENTS:
			return _fail("GS1 element count exceeds limit")
		out.append(e)
		pos = stop
	return out

static func _read_ai(value, pos, catalog):
	for n in [4, 3, 2]:
		var ai = value.substr(pos, n)
		if ai.length() == n and catalog.has(ai):
			return catalog[ai]
	return null

static func parse_gs1_element_string(input):
	var value = _ascii_input(input, "GS1 element string")
	if Err.is_error(value):
		return value
	if value.contains("(") or value.contains(")"):
		return _fail("GS1 element string must be raw data without parentheses")
	var out = []
	var pos = 0
	var catalog = _catalog()
	while pos < value.length():
		if value.substr(pos, 1) == GS1_FNC1_SEPARATOR:
			return _fail("Unexpected FNC1 separator at offset %d" % pos, "GS1_UNEXPECTED_SEPARATOR")
		var info = _read_ai(value, pos, catalog)
		if info == null:
			return _fail("Unsupported GS1 AI at offset %d" % pos, "GS1_UNSUPPORTED_AI")
		var start = pos + info.ai.length()
		var stop = value.find(GS1_FNC1_SEPARATOR, start) if info.length.isVariable else mini(start + info.length.exact, value.length())
		if stop < 0:
			stop = value.length()
		if info.length.isVariable and stop == value.length():
			for offset in range(maxi(start + 1, stop - 22), stop):
				var tail = _read_ai(value, offset, catalog)
				if tail != null and not tail.length.isVariable and offset + tail.ai.length() + tail.length.exact == stop:
					return _fail("GS1 variable field is missing an FNC1 separator before offset %d" % offset, "GS1_MISSING_SEPARATOR")
		var e = _element({"ai": info.ai, "value": value.substr(start, stop - start)}, out.size(), catalog)
		if Err.is_error(e):
			return e
		if out.size() >= GS1_MAX_ELEMENTS:
			return _fail("GS1 element count exceeds limit")
		out.append(e)
		pos = stop
		if info.length.isVariable and pos < value.length():
			pos += 1
			if pos >= value.length():
				return _fail("GS1 element string must not end with an FNC1 separator", "GS1_UNEXPECTED_SEPARATOR")
	return {"elements": out, "hasSeparators": value.contains(GS1_FNC1_SEPARATOR)}

static func create_gs1_element_string(input):
	var values = normalize_gs1_elements(input)
	if Err.is_error(values):
		return values
	var pieces = PackedStringArray()
	var length = 0
	var catalog = _catalog()
	for i in range(values.size()):
		var e = values[i]
		var piece = e.ai + e.value
		if i < values.size() - 1 and catalog[e.ai].length.isVariable:
			piece += GS1_FNC1_SEPARATOR
		length += piece.length()
		if length > GS1_MAX_INPUT_CHARACTERS:
			return _fail("GS1 output exceeds character budget")
		pieces.append(piece)
	return "".join(pieces)

static func gs1_to_human_readable(input):
	var values = normalize_gs1_elements(input)
	if Err.is_error(values):
		return values
	var pieces = PackedStringArray()
	for e in values:
		pieces.append("(" + e.ai + ")" + e.value)
	return _text("".join(pieces), "GS1 output")

static func gs1_element_string_to_human_readable(input):
	var parsed = parse_gs1_element_string(input)
	return parsed if Err.is_error(parsed) else gs1_to_human_readable(parsed.elements)

const REASONS = {
	"GS1_UNSUPPORTED_AI": "unsupported-ai", "GS1_INVALID_LENGTH": "invalid-length", "GS1_INVALID_CHARSET": "invalid-charset",
	"GS1_MISSING_SEPARATOR": "missing-separator", "GS1_UNEXPECTED_SEPARATOR": "unexpected-separator", "GS1_INVALID_CHECK_DIGIT": "invalid-check-digit",
	"GS1_INVALID_PERCENT_ENCODING": "invalid-percent-encoding", "GS1_INVALID_DIGITAL_LINK_PLACEMENT": "invalid-digital-link-placement",
	"GS1_DUPLICATE_AI": "duplicate-ai", "GS1_DIGITAL_LINK_UNKNOWN_QUERY": "unknown-query", "GS1_DIGITAL_LINK_UNSUPPORTED_HOST": "unsupported-host",
	"GS1_DIGITAL_LINK_INVALID_URI": "invalid-uri", "GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED": "fragment-not-allowed"}

static func _issue(error, element = null, index = null):
	var code = error.get("detailCode", "GS1_INVALID_INPUT")
	var message = error.message
	var out = {"code": code, "message": message, "reason": REASONS.get(code, "invalid-input"),
		"ai": null, "value": null, "key": null, "offset": null, "elementIndex": index, "expected": null, "count": null}
	if typeof(element) == TYPE_DICTIONARY:
		for field in ["ai", "value"]:
			var s = element.get(field)
			if typeof(s) == TYPE_STRING and s.length() <= (4 if field == "ai" else 90) and not Err.is_error(_text(s)):
				out[field] = s
	var regex = RegEx.new()
	regex.compile("GS1 AI ([0-9]{2,4})(?![0-9])")
	var found = regex.search(message)
	if out.ai == null and found != null:
		out.ai = found.get_string(1)
	regex.compile("offset ([0-9]+)")
	found = regex.search(message)
	if found != null:
		out.offset = int(found.get_string(1))
	if code == "GS1_DIGITAL_LINK_UNSUPPORTED_HOST":
		out.expected = "ASCII URL host or RFC IPv6; Unicode/IDNA hosts are unsupported"
	return out

static func _failure(error, digital = false):
	var out = {"ok": false, "errors": [_issue(error)], "warnings": []}
	if digital:
		out.result = null
	else:
		out.elements = null
		out.hasSeparators = null
	return out

static func _validation_options(input):
	var out = _options(input, ["context", "collectAllErrors", "allowUnsupportedAi"])
	if Err.is_error(out):
		return out
	out.context = _text(out.get("context", "element-string"), "GS1 context")
	if Err.is_error(out.context):
		return out.context
	if out.context != "element-string" and out.context != "digital-link":
		return _fail("GS1 validation context must be element-string or digital-link")
	out.collectAllErrors = _boolean(out.get("collectAllErrors", true), "GS1 collectAllErrors")
	if Err.is_error(out.collectAllErrors):
		return out.collectAllErrors
	if out.has("allowUnsupportedAi"):
		var allow = _boolean(out.allowUnsupportedAi, "GS1 allowUnsupportedAi")
		if Err.is_error(allow):
			return allow
		if allow:
			return _fail("GS1 validation allowUnsupportedAi must be false")
	return out

static func validate_gs1_elements(input, options = null):
	var opts = _validation_options(options)
	if Err.is_error(opts):
		return _failure(opts)
	var bounded = _bounded_elements(input)
	if Err.is_error(bounded):
		return _failure(bounded)
	if input.is_empty():
		return _failure(_fail("GS1 elements must not be empty"))
	var normal = []
	var errors = []
	var catalog = _catalog()
	var has_primary = false
	for i in range(input.size()):
		var e = _element(input[i], i, catalog)
		if Err.is_error(e):
			errors.append(_issue(e, input[i], i))
			if not opts.collectAllErrors:
				break
		else:
			normal.append(e)
			has_primary = has_primary or _primary(e.ai)
	if not errors.is_empty():
		return {"ok": false, "elements": null, "hasSeparators": null, "errors": errors, "warnings": []}
	if opts.context == "digital-link" and not has_primary:
		return _failure(_fail("GS1 Digital Link requires primary AI 00, 01, or 414", "GS1_INVALID_DIGITAL_LINK_PLACEMENT"))
	return {"ok": true, "elements": normal, "hasSeparators": null, "errors": [], "warnings": []}

static func validate_gs1_element_string(input, options = null):
	var opts = _validation_options(options)
	if Err.is_error(opts):
		return _failure(opts)
	var parsed = parse_gs1_element_string(input)
	if Err.is_error(parsed):
		return _failure(parsed)
	var result = validate_gs1_elements(parsed.elements, options)
	result.hasSeparators = parsed.hasSeparators
	return result

static func _percent_fail():
	return _fail("GS1 URI must use valid percent-encoding and UTF-8 without NUL", "GS1_INVALID_PERCENT_ENCODING")

static func _hex(c):
	if c >= 48 and c <= 57:
		return c - 48
	if c >= 65 and c <= 70:
		return c - 55
	if c >= 97 and c <= 102:
		return c - 87
	return -1

static func _valid_utf8(bytes):
	var pos = 0
	while pos < bytes.size():
		var first = bytes[pos]
		if first == 0:
			return false
		if first < 128:
			pos += 1
			continue
		var count = 0
		var cp = 0
		var minimum = 0
		if first >= 0xc2 and first <= 0xdf:
			count = 1
			cp = first & 31
			minimum = 0x80
		elif first >= 0xe0 and first <= 0xef:
			count = 2
			cp = first & 15
			minimum = 0x800
		elif first >= 0xf0 and first <= 0xf4:
			count = 3
			cp = first & 7
			minimum = 0x10000
		else:
			return false
		if pos + count >= bytes.size():
			return false
		for i in range(1, count + 1):
			var next = bytes[pos + i]
			if next < 0x80 or next > 0xbf:
				return false
			cp = (cp << 6) | (next & 63)
		if cp < minimum or cp > 0x10ffff or (cp >= 0xd800 and cp <= 0xdfff):
			return false
		pos += count + 1
	return true

static func _decode(value, form = false):
	var bytes = value.to_utf8_buffer()
	var out = PackedByteArray()
	var pos = 0
	while pos < bytes.size():
		var b = bytes[pos]
		if b == 37:
			if pos + 2 >= bytes.size():
				return _percent_fail()
			var high = _hex(bytes[pos + 1])
			var low = _hex(bytes[pos + 2])
			if high < 0 or low < 0:
				return _percent_fail()
			out.append((high << 4) | low)
			pos += 3
		else:
			out.append(32 if form and b == 43 else b)
			pos += 1
	if not _valid_utf8(out):
		return _percent_fail()
	return out.get_string_from_utf8()

static func _encode(value, form = false):
	var pieces = PackedStringArray()
	for b in value.to_utf8_buffer():
		var safe = (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or b == 42 or b == 46 or b == 95 or b == 45
		if not form and (b == 126 or b == 33 or b == 39 or b == 40 or b == 41):
			safe = true
		if form and b == 32:
			pieces.append("+")
		elif safe:
			pieces.append(String.chr(b))
		else:
			pieces.append("%%%02X" % b)
	return "".join(pieces)

static func _split(value, separator, limit):
	if value.count(separator) >= limit:
		return _fail("GS1 URL component count exceeds limit")
	return Array(value.split(separator, true))

static func _pair(value):
	var at = value.find("=")
	var key = _decode(value if at < 0 else value.left(at), true)
	if Err.is_error(key):
		return key
	var decoded = "" if at < 0 else _decode(value.substr(at + 1), true)
	if Err.is_error(decoded):
		return decoded
	return {"key": key, "value": decoded}

static func _match(value, pattern):
	var regex = RegEx.new()
	regex.compile(pattern)
	return regex.search(value) != null

static func _ipv4(value):
	var parts = value.split(".", true)
	if parts.size() != 4:
		return false
	for part in parts:
		if not _match(part, "^(?:0|[1-9][0-9]{0,2})$") or int(part) > 255:
			return false
	return true

static func _ipv6_side(value, allow_ipv4 = false):
	if value == "":
		return 0
	var parts = value.split(":", true)
	var count = 0
	for i in range(parts.size()):
		var part = parts[i]
		if part == "":
			return -1
		if part.contains("."):
			if not allow_ipv4 or i != parts.size() - 1 or not _ipv4(part):
				return -1
			count += 2
		else:
			if not _match(part, "^[0-9A-Fa-f]{1,4}$"):
				return -1
			count += 1
	return count

static func _ipv6(value):
	var parts = value.split("::", true)
	if parts.size() == 1:
		return _ipv6_side(parts[0], true) == 8
	if parts.size() == 2:
		var a = _ipv6_side(parts[0])
		var b = _ipv6_side(parts[1], true)
		return a >= 0 and b >= 0 and a + b < 8
	return false

static func _host_fail():
	return _fail("Unsupported host profile; use an ASCII URL host or RFC IPv6", "GS1_DIGITAL_LINK_UNSUPPORTED_HOST")

static func _ipv4_number(value):
	# -1 means non-numeric. 2^32 is an overflow sentinel, never a wrapped value.
	if value.is_empty():
		return -1
	var radix = 10
	if value.length() >= 2 and value.left(2).to_lower() == "0x":
		radix = 16
		value = value.substr(2)
	elif value.length() >= 2 and value.begins_with("0"):
		radix = 8
		value = value.substr(1)
	var number = 0
	for i in range(value.length()):
		var digit = _hex(value.unicode_at(i))
		if digit < 0 or digit >= radix:
			return -1
		if number < 0x100000000:
			if number > int((0xffffffff - digit) / radix):
				number = 0x100000000
			else:
				number = number * radix + digit
	return number

static func _normalize_ipv4_host(host):
	var parts = Array(host.split(".", true))
	if parts.size() > 1 and parts[parts.size() - 1] == "":
		parts.pop_back()
	var last = parts[parts.size() - 1]
	# A non-numeric final label is a domain/reg-name, not an IPv4 candidate.
	if not _digits(last) and _ipv4_number(last) < 0:
		return host
	if parts.size() > 4:
		return _host_fail()
	var numbers = []
	for part in parts:
		var number = _ipv4_number(part)
		if number < 0 or number > 0xffffffff:
			return _host_fail()
		numbers.append(number)
	for i in range(numbers.size() - 1):
		if numbers[i] > 255:
			return _host_fail()
	if numbers[numbers.size() - 1] >= (1 << (8 * (5 - numbers.size()))):
		return _host_fail()
	var address = numbers[numbers.size() - 1]
	for i in range(numbers.size() - 1):
		address += numbers[i] << (8 * (3 - i))
	return "%d.%d.%d.%d" % [(address >> 24) & 255, (address >> 16) & 255, (address >> 8) & 255, address & 255]

static func _ipv6_groups(side):
	var groups = []
	if side == "":
		return groups
	for part in side.split(":", true):
		if part.contains("."):
			var bytes = part.split(".")
			groups.append((int(bytes[0]) << 8) | int(bytes[1]))
			groups.append((int(bytes[2]) << 8) | int(bytes[3]))
		else:
			groups.append(part.hex_to_int())
	return groups

static func _normalize_ipv6(address):
	# Called only after complete IPv6 validation, including embedded IPv4.
	var sides = address.split("::", true)
	var groups = _ipv6_groups(sides[0])
	if sides.size() == 2:
		var right = _ipv6_groups(sides[1])
		var missing = 8 - groups.size() - right.size()
		for _i in range(missing):
			groups.append(0)
		groups.append_array(right)
	var best_start = -1
	var best_size = 1
	var at = 0
	while at < groups.size():
		if groups[at] != 0:
			at += 1
			continue
		var start = at
		while at < groups.size() and groups[at] == 0:
			at += 1
		if at - start > best_size:
			best_start = start
			best_size = at - start
	var pieces = PackedStringArray()
	for group in groups:
		pieces.append("%x" % group)
	if best_start < 0:
		return ":".join(pieces)
	var left = ":".join(pieces.slice(0, best_start))
	var right = ":".join(pieces.slice(best_start + best_size))
	return left + "::" + right

static func _userinfo_encode(value):
	var out = PackedStringArray()
	for i in range(value.length()):
		var cp = value.unicode_at(i)
		var character = value.substr(i, 1)
		if cp <= 32 or cp >= 127 or cp in [34, 35, 47, 58, 59, 60, 61, 62, 63, 64, 91, 92, 93, 94, 96, 123, 124, 125]:
			for byte in character.to_utf8_buffer():
				out.append("%%%02X" % byte)
		else:
			out.append(character)
	return "".join(out)

static func _authority(value, scheme):
	if value.length() < 1 or value.length() > 1024:
		return _host_fail()
	var userinfo = ""
	var at_sign = value.rfind("@")
	if at_sign >= 0:
		var raw_userinfo = value.left(at_sign)
		# Validate escapes strictly without decoding/re-encoding credential bytes.
		var decoded_userinfo = _decode(raw_userinfo)
		if Err.is_error(decoded_userinfo):
			return decoded_userinfo
		var colon = raw_userinfo.find(":")
		var username = _userinfo_encode(raw_userinfo if colon < 0 else raw_userinfo.left(colon))
		var password = "" if colon < 0 else _userinfo_encode(raw_userinfo.substr(colon + 1))
		if username != "" or password != "":
			userinfo = username + ((":" + password) if password != "" else "") + "@"
		value = value.substr(at_sign + 1)
	var host = ""
	var port = null
	if value.begins_with("["):
		var close = value.find("]")
		if close < 0:
			return _host_fail()
		var address = value.substr(1, close - 1)
		if not _ipv6(address):
			return _host_fail()
		host = "[" + _normalize_ipv6(address) + "]"
		var tail = value.substr(close + 1)
		if not tail.is_empty():
			if not tail.begins_with(":"):
				return _host_fail()
			port = tail.substr(1)
	else:
		var at = value.find(":")
		var raw_host = value if at < 0 else value.left(at)
		if at >= 0:
			port = value.substr(at + 1)
		host = _decode(raw_host)
		if Err.is_error(host):
			return host
		if host.is_empty():
			return _host_fail()
		# No partial IDNA: non-ASCII hosts require full UTS46 support and remain
		# an explicit host limit. ASCII URL reg-names need not be DNS labels.
		for i in range(host.length()):
			var cp = host.unicode_at(i)
			if cp <= 32 or cp >= 127 or cp in [35, 37, 47, 58, 60, 62, 63, 64, 91, 92, 93, 94, 124]:
				return _host_fail()
		host = _normalize_ipv4_host(host.to_lower())
		if Err.is_error(host):
			return host
	if port != null and port != "":
		if not _digits(port):
			return _fail("GS1 port must contain decimal digits from 0 to 65535", "GS1_DIGITAL_LINK_INVALID_URI")
		var n = 0
		for i in range(port.length()):
			n = n * 10 + port.unicode_at(i) - 48
			if n > 65535:
				return _fail("GS1 port must be from 0 to 65535", "GS1_DIGITAL_LINK_INVALID_URI")
		if not ((scheme == "http" and n == 80) or (scheme == "https" and n == 443)):
			host += ":" + str(n)
	return userinfo + host

static func _url_source(value):
	# HTTP(S) URL lexical repairs: trim edge ASCII controls/spaces and remove
	# TAB/LF/CR anywhere. NUL remains a deliberate strict decoding rejection.
	for i in range(value.length()):
		if value.unicode_at(i) == 0:
			return _percent_fail()
	var start = 0
	var end = value.length()
	while start < end and value.unicode_at(start) <= 32:
		start += 1
	while end > start and value.unicode_at(end - 1) <= 32:
		end -= 1
	return value.substr(start, end - start).replace("\t", "").replace("\n", "").replace("\r", "")

static func _url_path(value):
	# Serialize only raw characters from the URL path percent-encode set.
	# Existing percent escapes remain intact and are validated by _decode.
	var out = PackedStringArray()
	for i in range(value.length()):
		var cp = value.unicode_at(i)
		var character = value.substr(i, 1)
		if cp <= 32 or cp >= 127 or cp in [34, 35, 60, 62, 63, 96, 123, 125]:
			for byte in character.to_utf8_buffer():
				out.append("%%%02X" % byte)
		else:
			out.append(character)
	return "".join(out)

static func _url(input):
	var value = _text(input, "GS1 Digital Link URI")
	if Err.is_error(value):
		return value
	value = _url_source(value)
	if Err.is_error(value):
		return value
	var fragment_at = value.find("#")
	var empty_fragment = fragment_at >= 0
	if fragment_at >= 0:
		if fragment_at != value.length() - 1:
			return _fail("GS1 Digital Link URI must not include a fragment", "GS1_DIGITAL_LINK_FRAGMENT_NOT_ALLOWED")
		value = value.left(fragment_at)
	# A query backslash is data. Only authority/path backslashes are slashes.
	var query_at = value.find("?")
	var head = value if query_at < 0 else value.left(query_at)
	var query = null if query_at < 0 else value.substr(query_at + 1)
	head = head.replace("\\", "/")
	var regex = RegEx.new()
	regex.compile("^([Hh][Tt][Tt][Pp][Ss]?):/*([^/]*)(.*)$")
	var found = regex.search(head)
	if found == null:
		return _fail("GS1 URI must be an absolute http or https URL", "GS1_DIGITAL_LINK_INVALID_URI")
	var scheme = found.get_string(1).to_lower()
	var authority = _authority(found.get_string(2), scheme)
	if Err.is_error(authority):
		return authority
	var path = _url_path(found.get_string(3))
	var parts = _split(path, "/", 2 * GS1_MAX_ELEMENTS + 1)
	if Err.is_error(parts):
		return parts
	for part in parts:
		var decoded = _decode(part)
		if Err.is_error(decoded):
			return decoded
	if query != null:
		parts = _split(query, "&", GS1_MAX_ELEMENTS)
		if Err.is_error(parts):
			return parts
		for part in parts:
			var decoded = _pair(part)
			if Err.is_error(decoded):
				return decoded
	return {"scheme": scheme, "authority": authority, "path": path, "query": query, "emptyFragment": empty_fragment}

static func _url_base(url):
	return url.scheme + "://" + url.authority

static func _check_primary(input):
	var value = _text(input, "GS1 primaryAi")
	if Err.is_error(value):
		return value
	if not _primary(value):
		return _fail("GS1 primaryAi must be one of 00, 01, or 414")
	return value

static func _policy(input):
	var value = _text(input, "GS1 unknownQuery")
	if Err.is_error(value):
		return value
	if value != "preserve" and value != "reject":
		return _fail("GS1 unknownQuery must be preserve or reject")
	return value

static func _placement(ai, primary, catalog):
	if not catalog.has(ai):
		return _fail("Unsupported GS1 AI " + ai, "GS1_UNSUPPORTED_AI")
	if not _eligible(ai, primary):
		return _fail("GS1 AI %s cannot be placed in the Digital Link path after primary AI %s" % [ai, primary], "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
	return true

static func _unique(seen, ai):
	if seen.has(ai):
		return _fail("GS1 Digital Link must not contain duplicate AI " + ai, "GS1_DUPLICATE_AI")
	seen[ai] = true
	return true

static func _prefix(parts):
	var stack = PackedStringArray()
	for part in parts:
		var decoded = _decode(part)
		if Err.is_error(decoded):
			return decoded
		if decoded == "" or decoded == ".":
			continue
		if decoded == "..":
			if not stack.is_empty():
				stack.remove_at(stack.size() - 1)
		else:
			stack.append(part)
	return "" if stack.is_empty() else "/" + "/".join(stack)

static func _path_parts(path):
	var start = 0
	var end = path.length()
	while start < end and path.substr(start, 1) == "/":
		start += 1
	while end > start and path.substr(end - 1, 1) == "/":
		end -= 1
	path = path.substr(start, end - start)
	if path.is_empty():
		return _fail("GS1 Digital Link path must include primary AI 00, 01, or 414", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
	var parts = _split(path, "/", 2 * GS1_MAX_ELEMENTS + 1)
	if Err.is_error(parts):
		return parts
	if parts.has(""):
		return _fail("GS1 Digital Link path must not contain empty segments")
	return parts

static func _first_ai(parts, primary):
	for i in range(parts.size()):
		if (_primary(parts[i]) if primary == "" else parts[i] == primary):
			return i
	return _fail("GS1 Digital Link path must include primary AI 00, 01, or 414", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")

static func create_gs1_digital_link(elements, options = null):
	var opts = _options(options, ["baseUrl", "primaryAi", "pathAis", "explicitPathAis"])
	if Err.is_error(opts):
		return opts
	var primary = _check_primary(opts.get("primaryAi", "01"))
	if Err.is_error(primary):
		return primary
	var base = _url(opts.get("baseUrl", "https://id.gs1.org"))
	if Err.is_error(base):
		return base
	if base.query != null and base.query != "":
		return _fail("GS1 Digital Link baseUrl must not include query components")
	var ais = _array(opts.get("pathAis", []), "GS1 pathAis")
	if Err.is_error(ais):
		return ais
	var explicit = opts.has("pathAis")
	if opts.has("explicitPathAis"):
		explicit = _boolean(opts.explicitPathAis, "GS1 explicitPathAis")
		if Err.is_error(explicit):
			return explicit
	var paths = {}
	var catalog = _catalog()
	for entry in ais:
		var ai = _text(entry, "GS1 pathAis entry")
		if Err.is_error(ai):
			return ai
		if not _is_ai(ai):
			return _fail("GS1 pathAis entries must be 2 to 4 digit AI strings")
		if ai != primary:
			var placed = _placement(ai, primary, catalog)
			if Err.is_error(placed):
				return placed
			paths[ai] = true
	var values = normalize_gs1_elements(elements)
	if Err.is_error(values):
		return values
	var seen = {}
	var selected = -1
	for i in range(values.size()):
		var unique = _unique(seen, values[i].ai)
		if Err.is_error(unique):
			return unique
		if values[i].ai == primary:
			selected = i
	if selected < 0:
		return _fail("GS1 input must include primary AI " + primary, "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
	var path = [values[selected]]
	var query = []
	for i in range(values.size()):
		if i == selected:
			continue
		var e = values[i]
		var in_path = paths.has(e.ai) if explicit or not ais.is_empty() else _eligible(e.ai, primary)
		if in_path and e.value != "." and e.value != "..":
			var placed = _placement(e.ai, primary, catalog)
			if Err.is_error(placed):
				return placed
			path.append(e)
		else:
			query.append(e)
	query.sort_custom(func(a, b): return a.ai < b.ai or (a.ai == b.ai and a.value < b.value))
	var base_parts = _split(base.path, "/", 2 * GS1_MAX_ELEMENTS + 1)
	if Err.is_error(base_parts):
		return base_parts
	var stem = _prefix(base_parts)
	if Err.is_error(stem):
		return stem
	for part in stem.split("/", true):
		if _primary(_decode(part)):
			return _fail("GS1 base URL normalized path must not contain a primary AI component (00, 01, or 414), including percent-encoded equivalents", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
	var pieces = PackedStringArray([_url_base(base), stem])
	for e in path:
		pieces.append("/" + _encode(e.ai) + "/" + _encode(e.value))
	if not query.is_empty():
		var pairs = PackedStringArray()
		for e in query:
			pairs.append(_encode(e.ai, true) + "=" + _encode(e.value, true))
		pieces.append("?" + "&".join(pairs))
	if base.emptyFragment:
		pieces.append("#")
	return _text("".join(pieces), "GS1 Digital Link output")

static func _parse_link(url, primary, policy):
	if primary.length() > 0:
		var checked = _check_primary(primary)
		if Err.is_error(checked):
			return checked
	var checked = _policy(policy)
	if Err.is_error(checked):
		return checked
	var parts = _path_parts(url.path)
	if Err.is_error(parts):
		return parts
	var start = _first_ai(parts, primary)
	if Err.is_error(start):
		return start
	# Reject before normalization can erase payload, including encoded dot forms.
	for i in range(start, parts.size()):
		var decoded = _decode(parts[i])
		if Err.is_error(decoded):
			return decoded
		if decoded == "." or decoded == "..":
			return _fail("GS1 Digital Link path values must not be dot segments; place these values in the query", "GS1_INVALID_DIGITAL_LINK_PLACEMENT")
	if (parts.size() - start) % 2 != 0:
		return _fail("GS1 Digital Link path must contain AI/value pairs")
	var seen = {}
	var path = []
	var query = []
	var unknown = []
	var catalog = _catalog()
	for i in range(start, parts.size(), 2):
		var ai = parts[i]
		if not _is_ai(ai):
			return _fail("GS1 Digital Link path segment %d must be a GS1 AI" % (i + 1))
		var decoded = _decode(parts[i + 1])
		if Err.is_error(decoded):
			return decoded
		var e = _element({"ai": ai, "value": decoded}, path.size(), catalog)
		if Err.is_error(e):
			return e
		if not path.is_empty():
			checked = _placement(ai, path[0].ai, catalog)
			if Err.is_error(checked):
				return checked
		checked = _unique(seen, ai)
		if Err.is_error(checked):
			return checked
		if path.size() >= GS1_MAX_ELEMENTS:
			return _fail("GS1 element count exceeds limit")
		path.append(e)
	if url.query != null:
		var query_parts = _split(url.query, "&", GS1_MAX_ELEMENTS)
		if Err.is_error(query_parts):
			return query_parts
		for raw in query_parts:
			if raw == "":
				continue
			var pair = _pair(raw)
			if Err.is_error(pair):
				return pair
			if _is_ai(pair.key):
				var e = _element({"ai": pair.key, "value": pair.value}, path.size() + query.size(), catalog)
				if Err.is_error(e):
					return e
				checked = _unique(seen, e.ai)
				if Err.is_error(checked):
					return checked
				query.append(e)
			elif policy == "preserve":
				unknown.append(pair)
			else:
				return _fail("GS1 Digital Link query parameter is not a GS1 AI", "GS1_DIGITAL_LINK_UNKNOWN_QUERY")
			if path.size() + query.size() + unknown.size() > GS1_MAX_ELEMENTS:
				return _fail("GS1 element and query pair count exceeds limit")
	return {"elements": path + query, "primary": path[0].duplicate(), "pathElements": path, "queryElements": query, "unknownQuery": unknown}

static func _link_options(options, extra = []):
	var opts = _options(options, ["primaryAi", "unknownQuery"] + extra)
	if Err.is_error(opts):
		return opts
	opts.primaryAi = _text(opts.get("primaryAi", ""), "GS1 primaryAi")
	if Err.is_error(opts.primaryAi):
		return opts.primaryAi
	opts.unknownQuery = _text(opts.get("unknownQuery", "preserve"), "GS1 unknownQuery")
	if Err.is_error(opts.unknownQuery):
		return opts.unknownQuery
	return opts

static func parse_gs1_digital_link(input, options = null):
	var opts = _link_options(options)
	if Err.is_error(opts):
		return opts
	var url = _url(input)
	return url if Err.is_error(url) else _parse_link(url, opts.primaryAi, opts.unknownQuery)

static func validate_gs1_digital_link(input, options = null):
	var opts = _link_options(options, ["normalize"])
	if Err.is_error(opts):
		return _failure(opts, true)
	if opts.has("normalize"):
		var normalize = _boolean(opts.normalize, "GS1 normalize")
		if Err.is_error(normalize):
			return _failure(normalize, true)
		if normalize:
			return _failure(_fail("GS1 validation normalize is unsupported; call normalize_gs1_digital_link"), true)
	var url = _url(input)
	if Err.is_error(url):
		return _failure(url, true)
	var parsed = _parse_link(url, opts.primaryAi, opts.unknownQuery)
	if Err.is_error(parsed):
		return _failure(parsed, true)
	var warnings = []
	if url.scheme == "http":
		warnings.append({"code": "GS1_DIGITAL_LINK_HTTP", "message": "URI uses HTTP; use HTTPS when transport security is required", "reason": "http-uri"})
	if not parsed.unknownQuery.is_empty():
		warnings.append({"code": "GS1_DIGITAL_LINK_UNKNOWN_QUERY_PRESERVED", "message": "Non-GS1 query parameters are preserved", "reason": "unknown-query-preserved", "count": parsed.unknownQuery.size()})
	return {"ok": true, "result": parsed, "errors": [], "warnings": warnings}

static func normalize_gs1_digital_link(input, options = null):
	var opts = _link_options(options, ["mode"])
	if Err.is_error(opts):
		return opts
	var mode = _text(opts.get("mode", "specqr-deterministic"), "GS1 mode")
	if Err.is_error(mode):
		return mode
	if mode != "specqr-deterministic":
		return _fail("GS1 normalization mode must be specqr-deterministic")
	var url = _url(input)
	if Err.is_error(url):
		return url
	var parsed = _parse_link(url, opts.primaryAi, opts.unknownQuery)
	if Err.is_error(parsed):
		return parsed
	var parts = _path_parts(url.path)
	var start = _first_ai(parts, opts.primaryAi)
	var stem = _prefix(parts.slice(0, start))
	if Err.is_error(stem):
		return stem
	var out = create_gs1_digital_link(parsed.elements, {"baseUrl": _url_base(url) + stem, "primaryAi": parsed.primary.ai})
	if Err.is_error(out):
		return out
	var pieces = PackedStringArray([out])
	var has_query = out.contains("?")
	for pair in parsed.unknownQuery:
		pieces.append(("&" if has_query else "?") + _encode(pair.key, true) + "=" + _encode(pair.value, true))
		has_query = true
	return _text("".join(pieces), "GS1 Digital Link output")

static func gs1_normalize(input):
	return normalize_gs1_elements(input)

static func gs1_from_human_readable(input):
	return parse_gs1_human_readable(input)

static func gs1_to_element_string(input):
	return create_gs1_element_string(input)

static func gs1_build(input):
	return create_gs1_element_string(input)

static func gs1_parse(input):
	return parse_gs1_element_string(input)

static func gs1_digital_link(input, options = null):
	return create_gs1_digital_link(input, options)

static func gs1_to_digital_link(input, options = null):
	return create_gs1_digital_link(input, options)
