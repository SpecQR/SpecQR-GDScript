extends SceneTree
## Run: godot --headless --no-header --path . --script script/cli.gd -- --text HELLO
const Q = preload("../addons/specqr/api.gd")
const S = preload("../addons/specqr/segments.gd")
const R = preload("../addons/specqr/render.gd")
const A = preload("../addons/specqr/structured_append.gd")
const E = preload("../addons/specqr/error.gd")
const J = preload("strict_json.gd")
const HELP = """SpecQR GDScript 0.1.0 (Godot 4.3+ standard engine required)
Usage: godot --headless --no-header --path . --script script/cli.gd -- [options]
  --text TEXT | --text-file FILE | --bytes-file FILE
  --format svg|png|svg-data-url|png-data-url|matrix|json (default svg)
  --output FILE    Required for binary PNG; text formats otherwise use stdout
  --ecc L|M|Q|H --version 1..40 --min-version N --max-version N --mask 0..7
  --mode auto|numeric|alphanumeric|byte|kanji --eci N
  --gs1 --fnc1 --fnc1-second A --boost --no-optimize --no-kanji
  --margin N --scale N --foreground COLOR --background COLOR --print-dpi N
  --plan | --structured-append --max-symbols N (SA requires --format json)
  --help --version-info
Text files must be shortest-form UTF-8 without U+0000. Binary input preserves
all bytes. Paths are ordinary file paths, not stdin aliases. No plugin needed.
"""

func _initialize():
	var result = _main(OS.get_cmdline_user_args())
	if E.is_error(result):
		printerr(_error_line(result.code + ": " + result.message))
		quit(2)
	else: quit(0)

static func _error_line(message):
	var output = ""
	for i in range(message.length()):
		var cp = message.unicode_at(i)
		output += "\\u%04x" % cp if cp < 32 or cp in [127, 0x85, 0x2028, 0x2029] else message[i]
	return output

static func _integer(value):
	if value.length() < 1 or value.length() > 11 or not value.is_valid_int(): return E.error("INVALID_INPUT", "Option value must be a bounded integer")
	return value.to_int()

static func _read(path, binary):
	var input = FileAccess.open(path, FileAccess.READ)
	if input == null: return E.error("IO_ERROR", "Cannot open input file")
	var limit = S.MAX_PAYLOAD_UNITS * (1 if binary else 4)
	var length = input.get_length()
	if length > limit: return E.error("DATA_TOO_LONG", "Input file exceeds resource budget")
	var bytes = input.get_buffer(length)
	if bytes.size() != length: return E.error("IO_ERROR", "Could not read complete input file")
	input.close()
	return Array(bytes) if binary else S.decode_utf8(bytes)

static func _q_json(q):
	var rows = []
	for row in q.matrix:
		var out = ""
		for bit in row: out += "1" if bit else "0"
		rows.append(out)
	return {"version": q.version, "errorCorrectionLevel": q.errorCorrectionLevel, "maskPattern": q.maskPattern, "matrix": rows, "diagnostics": q.diagnostics}

static func _main(arguments):
	var opts = {}
	var source = ""
	var input = ""
	var target = ""
	var format = "svg"
	var planning = false
	var structured = false
	var maximum = 16
	var integers = {"--version":"version", "--min-version":"minVersion", "--max-version":"maxVersion", "--mask":"maskPattern", "--eci":"eciAssignment", "--margin":"margin", "--scale":"scale"}
	var strings = {"--ecc":"errorCorrectionLevel", "--mode":"mode", "--fnc1-second":"fnc1Second", "--foreground":"foreground", "--background":"background"}
	var flags = {"--gs1":["gs1",true], "--fnc1":["fnc1",true], "--no-optimize":["optimizeSegments",false], "--no-kanji":["allowKanji",false], "--boost":["boostErrorCorrection",true]}
	var i = 0
	while i < arguments.size():
		var arg = arguments[i]
		i += 1
		if arg == "--help" or arg == "-h": printraw(HELP); return null
		if arg == "--version-info": print("SpecQR GDScript 0.1.0; Godot " + str(Engine.get_version_info().string)); return null
		if arg == "--plan": planning = true; continue
		if arg == "--structured-append": structured = true; continue
		if flags.has(arg): opts[flags[arg][0]] = flags[arg][1]; continue
		if not integers.has(arg) and not strings.has(arg) and not arg in ["--text", "--text-file", "--bytes-file", "--output", "-o", "--format", "--print-dpi", "--max-symbols"]: return E.error("INVALID_INPUT", "Unknown option: " + arg)
		if i >= arguments.size(): return E.error("INVALID_INPUT", "Missing value for " + arg)
		var value = arguments[i]
		i += 1
		if arg in ["--text", "--text-file", "--bytes-file"]:
			if source != "": return E.error("INVALID_INPUT", "Specify exactly one input source")
			source = arg
			input = value
		elif arg in ["--output", "-o"]: target = value
		elif arg == "--format": format = value
		elif arg == "--max-symbols":
			maximum = _integer(value)
			if E.is_error(maximum): return maximum
		elif arg == "--print-dpi":
			if not value.is_valid_float(): return E.error("INVALID_INPUT", "DPI must be numeric")
			opts["printDpi"] = value.to_float()
		elif integers.has(arg):
			var number = _integer(value)
			if E.is_error(number): return number
			if arg == "--version" and not E.in_range(number,1,40): return E.error("INVALID_VERSION", "Version must be 1..40")
			if arg == "--mask" and not E.in_range(number,0,7): return E.error("INVALID_INPUT", "Mask must be 0..7")
			if arg == "--eci" and not E.in_range(number,0,999999): return E.error("INVALID_ECI", "ECI must be 0..999999")
			opts[integers[arg]] = number
		else: opts[strings[arg]] = value
	if source == "": return E.error("INVALID_INPUT", "An explicit text or byte input source is required")
	if not format in ["svg", "png", "svg-data-url", "png-data-url", "matrix", "json"]: return E.error("INVALID_OUTPUT", "Unsupported output format")
	if planning and structured: return E.error("INVALID_MODE", "Planning and Structured Append are separate operations")
	if structured and format != "json": return E.error("INVALID_OUTPUT", "Structured Append requires --format json")
	if format == "png" and target == "" and not planning: return E.error("INVALID_OUTPUT", "PNG requires --output FILE")
	var payload = input if source == "--text" else _read(input, source == "--bytes-file")
	if E.is_error(payload): return payload
	var output
	if planning:
		var result = Q.plan(payload, opts)
		if E.is_error(result): return result
		output = J.stringify(result) + "\n"
	elif structured:
		var result = A.generate_structured_append(payload, opts, maximum)
		if E.is_error(result): return result
		var symbols = []
		for q in result.symbols: symbols.append(_q_json(q))
		result.symbols = symbols
		output = J.stringify(result) + "\n"
	else:
		var q = Q.generate(payload, opts)
		if E.is_error(q): return q
		match format:
			"svg": output = R.to_svg(q)
			"png": output = R.to_png(q)
			"svg-data-url": output = R.to_svg_data_url(q)
			"png-data-url": output = R.to_png_data_url(q)
			"matrix": output = J.stringify(_q_json(q).matrix)
			"json": output = J.stringify(_q_json(q))
		if E.is_error(output): return output
		if typeof(output) == TYPE_STRING: output += "\n"
	if target != "":
		var file = FileAccess.open(target, FileAccess.WRITE)
		if file == null: return E.error("IO_ERROR", "Cannot open output file")
		file.store_buffer(output.to_utf8_buffer() if typeof(output) == TYPE_STRING else PackedByteArray(output))
		file.flush()
		var status = file.get_error()
		file.close()
		if status != OK: return E.error("IO_ERROR", "Cannot write output file")
	else: printraw(output)
	return null
