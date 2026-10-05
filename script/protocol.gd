extends RefCounted
## Language-neutral synthetic verification protocol, implemented entirely in GDScript.
const Err = preload("../addons/specqr/error.gd")
const Segments = preload("../addons/specqr/segments.gd")
const Tables = preload("../addons/specqr/tables.gd")
const Core = preload("../addons/specqr/core.gd")
const API = preload("../addons/specqr/api.gd")
const GS1 = preload("../addons/specqr/gs1.gd")
const Render = preload("../addons/specqr/render.gd")
const SA = preload("../addons/specqr/structured_append.gd")

static func bad(message):
	return Err.error("INVALID_INPUT", message)

static func wire_segment(r):
	if typeof(r) != TYPE_DICTIONARY: return bad("Expected segment object")
	var mode = r.get("mode")
	if typeof(mode) != TYPE_STRING: return bad("Mode must be a string")
	var value = r.get("text", r.get("data"))
	match mode:
		"numeric", "alphanumeric", "kanji":
			return Segments.new_segment(mode, value)
		"byte":
			if r.has("bytes"): return Segments.byte_segment(r.bytes)
			if typeof(value) == TYPE_ARRAY: return Segments.byte_segment(value)
			return Segments.new_segment("byte", value)
		"eci": return Segments.eci(r.get("assignmentNumber"))
		"fnc1": return Segments.fnc1()
		"fnc1-second": return Segments.fnc1_second(r.get("applicationIndicator"))
		"structured-append": return Segments.structured_append_segment(r.get("index"), r.get("total"), r.get("parity"))
	return Err.error("INVALID_MODE", "Unknown segment mode")

static func rows(matrix):
	var out = []
	for row in matrix:
		var line = ""
		for cell in row: line += "1" if cell else "0"
		out.append(line)
	return out

static func packed(matrix):
	var bytes = PackedByteArray()
	var value = 0
	var count = 0
	for row in matrix:
		for cell in row:
			value = (value << 1) | (1 if cell else 0)
			count += 1
			if count == 8:
				bytes.append(value)
				value = 0
				count = 0
	if count: bytes.append(value << (8 - count))
	return Marshalls.raw_to_base64(bytes)

static func hex_bytes(bytes):
	return PackedByteArray(bytes).hex_encode()

static func wire_symbol(q, request = {}):
	if Err.is_error(q): return q
	var segments = []
	for segment in q.segments:
		segments.append({"mode":segment.mode,"count":Segments.segment_count(segment)})
	var out = {"version":q.version,"ecc":q.errorCorrectionLevel,"mask":q.maskPattern,"data":hex_bytes(q.dataCodewords),"codewords":hex_bytes(q.codewords),"matrix":rows(q.matrix),"matrixPacked":packed(q.matrix),"segments":segments}
	if request.has("pngScale"):
		var opts = {}
		for key in ["margin", "scale", "foreground", "background"]: opts[key] = q.options[key]
		opts.scale = request.pngScale
		var png = Render.to_png(q, opts)
		if Err.is_error(png): return png
		out.png = png.hex_encode()
	if request.get("diagnostics", false): out.diagnostics = q.diagnostics
	if request.get("renders", false):
		out.svg = Render.to_svg(q)
		out.svgDataUrl = Render.to_svg_data_url(q)
		out.pngDataUrl = Render.to_png_data_url(q)
	return out

static func run_request(request):
	if typeof(request) != TYPE_DICTIONARY: return bad("Expected object")
	var r = request
	var command = r.get("command", "generate")
	if command == null: command = "generate"
	if typeof(command) != TYPE_STRING: return bad("Expected command string")
	if command == "gs1-fixture":
		var methods = {"dictionary":"get_supported_gs1_ais","info":"get_gs1_ai_info","checkDigit":"calculate_gs1_check_digit","validateCheckDigit":"validate_gs1_check_digit","gtinDigit":"calculate_gtin_check_digit","gtinAppend":"append_gtin_check_digit","gtinValidate":"validate_gtin_check_digit","ssccDigit":"calculate_sscc_check_digit","ssccAppend":"append_sscc_check_digit","ssccValidate":"validate_sscc_check_digit","human":"parse_gs1_human_readable","raw":"parse_gs1_element_string","create":"create_gs1_element_string","validateElements":"validate_gs1_elements","validateRaw":"validate_gs1_element_string","linkCreate":"create_gs1_digital_link","linkParse":"parse_gs1_digital_link","linkValidate":"validate_gs1_digital_link","linkNormalize":"normalize_gs1_digital_link"}
		var op = r.get("op")
		if not methods.has(op): return bad("Unknown GS1 fixture operation")
		var args = [] if op == "dictionary" else [r.get("elements",r.get("input"))]
		if op in ["validateElements","validateRaw","linkCreate","linkParse","linkValidate","linkNormalize"]: args.append(r.get("options",{}))
		var value = GS1.new().callv(methods[op],args)
		if Err.is_error(value): value = {"throws":{"code":value.code,"message":value.message}}
		return {"value":value}
	if command == "gf":
		var bytes = PackedByteArray()
		for a in range(256):
			for b in range(256): bytes.append(Core.gf_multiply(a,b))
		return {"bytes":bytes.hex_encode()}
	if command == "rs":
		var degree = r.get("degree")
		if not Err.in_range(degree,1,255): return bad("Invalid degree")
		degree = int(degree)
		var bytes = []
		for i in range(300): bytes.append((i*61+degree)&255)
		var divisor = Core.reed_solomon_divisor(degree)
		if Err.is_error(divisor): return divisor
		var remainder = Core.reed_solomon_remainder(bytes,degree)
		if Err.is_error(remainder): return remainder
		return {"generator":hex_bytes(divisor),"remainder":hex_bytes(remainder)}
	if command == "raw":
		var version = r.get("version")
		var ecc = r.get("ecc")
		var seed = r.get("seed")
		var mask = r.get("mask")
		if not Err.in_range(version,1,40): return Err.error("INVALID_VERSION","Invalid version")
		if typeof(ecc) != TYPE_STRING or ecc not in ["L","M","Q","H"]: return Err.error("INVALID_ECC_LEVEL","Invalid ECC")
		if not Err.in_range(seed,0,100): return bad("Invalid seed")
		if not (typeof(mask)==TYPE_STRING and mask == "auto") and not Err.in_range(mask,-1,7): return bad("Invalid mask")
		version = int(version)
		seed = int(seed)
		mask = -1 if typeof(mask)==TYPE_STRING and mask == "auto" else int(mask)
		var ordinal = "LMQH".find(ecc)
		var count = Tables.data_codeword_count(version,ecc)
		var bytes = []
		for i in range(count): bytes.append(0 if seed == 0 else 255 if seed == 1 else ((i*149+version*43+ordinal*89+seed*67)^(0 if seed>=11 else i>>(seed+1)))&255)
		var inter = Core.interleave_codewords(bytes,version,ecc)
		if Err.is_error(inter): return inter
		var q = Core.build_matrix(inter.codewords,version,ecc,mask)
		if Err.is_error(q): return q
		var penalties = []
		for penalty in q.maskPenalties: penalties.append(penalty.penalty)
		return {"data":hex_bytes(bytes),"codewords":hex_bytes(inter.codewords),"matrix":rows(q.matrix),"matrixPacked":packed(q.matrix),"mask":q.maskPattern,"penalty":q.penalty,"penalties":penalties}
	if command == "gs1-build":
		var value = GS1.create_gs1_element_string(r.get("elements"))
		return value if Err.is_error(value) else {"value":value}
	if command == "digital-link-build":
		var value = GS1.create_gs1_digital_link(r.get("elements"),r.get("linkOptions",{}))
		return value if Err.is_error(value) else {"value":value}
	if command == "digital-link-parse": return GS1.parse_gs1_digital_link(r.get("url"))
	if command == "digital-link-validate": return GS1.validate_gs1_digital_link(r.get("url"))
	if command == "digital-link-normalize":
		var value = GS1.normalize_gs1_digital_link(r.get("url"))
		return value if Err.is_error(value) else {"value":value}
	var rawopts = r.get("options",{})
	if rawopts == null: rawopts = {}
	if typeof(rawopts) != TYPE_DICTIONARY: return bad("Expected options object")
	var opts = rawopts.duplicate(true)
	for key in ["optimizeSegments","allowKanji","boostErrorCorrection","gs1","fnc1"]:
		if opts.has(key) and typeof(opts[key]) != TYPE_BOOL: return bad("Expected JSON boolean")
	if opts.has("version") and opts.version != null and not (typeof(opts.version)==TYPE_STRING and opts.version == "auto"):
		if not Err.in_range(opts.version,1,40): return Err.error("INVALID_VERSION","Invalid version")
	if opts.has("maskPattern") and opts.maskPattern != null and not (typeof(opts.maskPattern)==TYPE_STRING and opts.maskPattern == "auto"):
		if not Err.in_range(opts.maskPattern,0,7): return bad("Invalid mask")
	if opts.has("eci") and opts.eci != null and typeof(opts.eci) != TYPE_BOOL:
		if not Err.in_range(opts.eci,0,999999): return Err.error("INVALID_ECI","Invalid ECI")
	if opts.has("fnc1Second") and opts.fnc1Second != null:
		if typeof(opts.fnc1Second) != TYPE_STRING: return bad("FNC1 indicator must be a String")
		var indicator=Segments.fnc1_second(opts.fnc1Second)
		if Err.is_error(indicator): return indicator
	for key in ["version","maskPattern"]:
		if opts.has(key) and opts[key] == null: opts[key] = "auto"
	for key in ["eci","fnc1Second"]:
		if opts.has(key) and opts[key] == null: opts.erase(key)
	if command == "capacity":
		var normalized = API.normalize_options(opts)
		if Err.is_error(normalized): return normalized
		var capacity = API.get_capacity(normalized.version,normalized.errorCorrectionLevel,normalized.mode)
		if Err.is_error(capacity): return capacity
		return {"maximum":capacity.maximum,"dataCodewords":capacity.dataCodewords,"capacityBits":capacity.capacityBits,"countBits":capacity.characterCountBits}
	var manual = r.has("segments")
	var input = r.get("bytes",r.get("text",""))
	if manual:
		if typeof(r.segments) != TYPE_ARRAY: return bad("Segments must be an array")
		input = []
		for item in r.segments:
			var segment = wire_segment(item)
			if Err.is_error(segment): return segment
			input.append(segment)
	if command in ["estimate","plan"]:
		var plan = API.plan_segments(input,opts) if manual else API.plan(input,opts)
		if Err.is_error(plan): return plan
		return {"fits":plan.ok,"version":plan.capacityVersion,"requiredBits":plan.dataBitLength,"capacityBits":plan.capacityBits}
	if command == "structured-append":
		var maximum = opts.get("maxSymbols",16)
		opts.erase("maxSymbols")
		var result = SA.generate_segments_structured_append(input,opts,maximum) if manual else SA.generate_structured_append(input,opts,maximum)
		if Err.is_error(result): return result
		var symbols = []
		var versions = []
		var masks = []
		for symbol in result.symbols:
			var wire = wire_symbol(symbol,r)
			if Err.is_error(wire): return wire
			symbols.append(wire)
			versions.append(symbol.version)
			masks.append(symbol.maskPattern)
		return {"total":result.total,"parity":result.parity,"inputLength":result.inputLength,"byteLength":result.byteLength,"symbols":symbols,"versions":versions,"masks":masks}
	if command == "generate": return wire_symbol(API.generate_segments(input,opts) if manual else API.generate(input,opts),r)
	return bad("Unknown command")
