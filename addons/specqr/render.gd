extends RefCounted
## Dependency-free SVG, exact RGBA pixels and PNG (stored DEFLATE) rendering.
const Err = preload("error.gd")
const RASTER_PIXEL_BUDGET = 4 * 1024 * 1024
const SVG_CHARACTER_BUDGET = 8 * 1024 * 1024
const DATA_URL_CHARACTER_BUDGET = 32 * 1024 * 1024
const MAX_GEOMETRY_INTEGER = 1000000000

static func _integer(value, low, high, label):
	if not Err.is_integer(value) or value < low or value > high:
		return Err.error("INVALID_INPUT", "%s must be an integer in %d..%d" % [label, low, high])
	return int(value)

static func _options(raw):
	if raw == null:
		raw = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return Err.error("INVALID_INPUT", "Render options must be a dictionary")
	var opts = {"margin": 4, "scale": 8, "foreground": "#000000", "background": "#ffffff"}
	var seen = {}
	for key in raw:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return Err.error("INVALID_INPUT", "Render option keys must be String or StringName")
		if key.length() > 64:
			return Err.error("INVALID_INPUT", "Unknown render option")
		var name = String(key)
		if not opts.has(name):
			return Err.error("INVALID_INPUT", "Unknown render option: " + name)
		if seen.has(name):
			return Err.error("INVALID_INPUT", "Duplicate normalized render option")
		seen[name] = true
		opts[name] = raw[key]
	opts.margin = _integer(opts.margin, 0, MAX_GEOMETRY_INTEGER, "Margin")
	if Err.is_error(opts.margin):
		return opts.margin
	opts.scale = _integer(opts.scale, 1, MAX_GEOMETRY_INTEGER, "Scale")
	if Err.is_error(opts.scale):
		return opts.scale
	for key in ["foreground", "background"]:
		opts[key] = color_text(opts[key])
		if Err.is_error(opts[key]):
			return opts[key]
	return opts

static func _matrix(arg, raw = null):
	if typeof(arg) == TYPE_DICTIONARY:
		if raw == null and typeof(arg.get("options")) == TYPE_DICTIONARY:
			raw = {}
			for key in ["margin", "scale", "foreground", "background"]:
				raw[key] = arg.options.get(key)
		arg = arg.get("matrix")
	if typeof(arg) != TYPE_ARRAY or arg.size() < 21 or arg.size() > 177 or (arg.size() - 17) % 4 != 0:
		return Err.error("INVALID_INPUT", "Matrix must be a square array of 21..177 modules")
	var n = arg.size()
	for row in arg:
		if typeof(row) != TYPE_ARRAY or row.size() != n:
			return Err.error("INVALID_INPUT", "Matrix rows must have equal lengths")
		for bit in row:
			if typeof(bit) != TYPE_BOOL and not (Err.is_integer(bit) and (bit == 0 or bit == 1)):
				return Err.error("INVALID_INPUT", "Matrix module must be a boolean")
	var opts = _options(raw)
	return opts if Err.is_error(opts) else {"matrix": arg, "options": opts}

static func color_text(value):
	if typeof(value) != TYPE_STRING or value.length() > 64:
		return Err.error("INVALID_COLOR", "Color must be a short ASCII string")
	for i in range(value.length()):
		if value.unicode_at(i) > 127:
			return Err.error("INVALID_COLOR", "Color must be a short ASCII string")
	var start = 0
	var end = value.length()
	while start < end and ([9, 10, 11, 12, 13, 32].has(value.unicode_at(start))):
		start += 1
	while end > start and ([9, 10, 11, 12, 13, 32].has(value.unicode_at(end - 1))):
		end -= 1
	value = value.substr(start, end - start)
	var regex = RegEx.new()
	regex.compile("^(?:#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|[A-Za-z]+)$")
	if regex.search(value) == null:
		return Err.error("INVALID_COLOR", "Color must be hex or a simple ASCII CSS name")
	return value

static func parse_color(value, strict = true):
	if typeof(strict) != TYPE_BOOL:
		return Err.error("INVALID_INPUT", "strict must be a boolean")
	var checked = color_text(value)
	if Err.is_error(checked):
		return checked
	var color = checked.to_lower()
	if color == "black":
		return [0, 0, 0, 255]
	if color == "white":
		return [255, 255, 255, 255]
	if color == "transparent":
		return [0, 0, 0, 0]
	if color.begins_with("#"):
		color = color.substr(1)
		var out = []
		if color.length() <= 4:
			for i in range(color.length()):
				out.append(color.substr(i, 1).hex_to_int() * 17)
		else:
			for i in range(0, color.length(), 2):
				out.append(color.substr(i, 2).hex_to_int())
		if out.size() == 3:
			out.append(255)
		return out
	return Err.error("INVALID_COLOR", "Raster colors require hex, black, white, or transparent") if strict else null

static func contrast_ratio(foreground, background):
	for color in [foreground, background]:
		if typeof(color) != TYPE_ARRAY and typeof(color) != TYPE_PACKED_BYTE_ARRAY:
			return Err.error("INVALID_COLOR", "RGBA must be an array")
		if color.size() != 4:
			return Err.error("INVALID_COLOR", "RGBA requires four channels")
		for channel in color:
			if not Err.is_integer(channel) or channel < 0 or channel > 255:
				return Err.error("INVALID_COLOR", "Color channel is outside its supported range")
	var a = 0.0
	var b = 0.0
	var weights = [0.2126, 0.7152, 0.0722]
	for i in range(3):
		var back = background[i] / 255.0 * (background[3] / 255.0) + 1.0 - background[3] / 255.0
		var front = foreground[i] / 255.0 * (foreground[3] / 255.0) + back * (1.0 - foreground[3] / 255.0)
		var fl = front / 12.92 if front <= 0.04045 else pow((front + 0.055) / 1.055, 2.4)
		var bl = back / 12.92 if back <= 0.04045 else pow((back + 0.055) / 1.055, 2.4)
		a += fl * weights[i]
		b += bl * weights[i]
	return (a + 0.05) / (b + 0.05) if a > b else (b + 0.05) / (a + 0.05)

static func _geometry(matrix, opts, raster):
	var n = matrix.size()
	if opts.margin > int((MAX_GEOMETRY_INTEGER - n) / 2):
		return Err.error("INVALID_INPUT", "Render geometry exceeds bound")
	var span = n + 2 * opts.margin
	if opts.scale > int(MAX_GEOMETRY_INTEGER / span):
		return Err.error("INVALID_INPUT", "Render geometry exceeds bound")
	var dimension = span * opts.scale
	if raster and dimension > 2048:
		return Err.error("INVALID_INPUT", "Raster exceeds pixel budget")
	return dimension

static func geometry(arg, raw = null, raster = false):
	if typeof(raster) != TYPE_BOOL:
		return Err.error("INVALID_INPUT", "raster must be a boolean")
	var normalized = _matrix(arg, raw)
	return normalized if Err.is_error(normalized) else _geometry(normalized.matrix, normalized.options, raster)

static func to_svg(arg, raw = null):
	var normalized = _matrix(arg, raw)
	if Err.is_error(normalized):
		return normalized
	var matrix = normalized.matrix
	var opts = normalized.options
	var d = _geometry(matrix, opts, false)
	if Err.is_error(d):
		return d
	var scale = opts.scale
	var margin = opts.margin
	var pieces = PackedStringArray()
	pieces.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" role="img"><rect width="100%%" height="100%%" fill="%s"/><path fill="%s" d="' % [d, d, d, d, opts.background, opts.foreground])
	var length = pieces[0].length() + 9
	for y in range(matrix.size()):
		for x in range(matrix.size()):
			if matrix[y][x]:
				var piece = "M%d,%dh%dv%dh-%dz" % [(x + margin) * scale, (y + margin) * scale, scale, scale, scale]
				length += piece.length()
				if length > SVG_CHARACTER_BUDGET:
					return Err.error("INVALID_INPUT", "SVG exceeds character budget")
				pieces.append(piece)
	pieces.append('"/></svg>')
	return "".join(pieces)

static func _color_run(color, count):
	var bytes = PackedByteArray()
	bytes.resize(count * 4)
	for i in range(count):
		for channel in range(4):
			bytes[i * 4 + channel] = color[channel]
	return bytes

static func to_pixels(arg, raw = null):
	var normalized = _matrix(arg, raw)
	if Err.is_error(normalized):
		return normalized
	var matrix = normalized.matrix
	var opts = normalized.options
	var d = _geometry(matrix, opts, true)
	if Err.is_error(d):
		return d
	var fg = parse_color(opts.foreground)
	if Err.is_error(fg):
		return fg
	var bg = parse_color(opts.background)
	if Err.is_error(bg):
		return bg
	var scale = opts.scale
	var edge = _color_run(bg, opts.margin * scale)
	var blank = _color_run(bg, d)
	var dark = _color_run(fg, scale)
	var light = _color_run(bg, scale)
	var pixels = PackedByteArray()
	for _y in range(opts.margin * scale):
		pixels.append_array(blank)
	for row in matrix:
		var raster_row = edge.duplicate()
		for bit in row:
			raster_row.append_array(dark if bit else light)
		raster_row.append_array(edge)
		for _y in range(scale):
			pixels.append_array(raster_row)
	for _y in range(opts.margin * scale):
		pixels.append_array(blank)
	return {"width": d, "height": d, "pixels": pixels}

static func _crc32(data):
	var table = []
	for i in range(256):
		var c = i
		for _bit in range(8):
			c = (c >> 1) ^ (0xedb88320 if (c & 1) != 0 else 0)
		table.append(c)
	var crc = 0xffffffff
	for byte in data:
		crc = table[(crc ^ byte) & 255] ^ (crc >> 8)
	return (crc ^ 0xffffffff) & 0xffffffff

static func _adler32(data):
	var a = 1
	var b = 0
	var pos = 0
	while pos < data.size():
		var end = mini(pos + 5552, data.size())
		while pos < end:
			a += data[pos]
			b += a
			pos += 1
		a %= 65521
		b %= 65521
	return (b << 16) | a

static func _u32(value):
	return PackedByteArray([(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255])

static func _chunk(kind, data):
	var payload = kind.to_ascii_buffer()
	payload.append_array(data)
	var out = _u32(data.size())
	out.append_array(payload)
	out.append_array(_u32(_crc32(payload)))
	return out

static func to_png(arg, options = null):
	var normalized = _matrix(arg, options)
	if Err.is_error(normalized):
		return normalized
	var d = _geometry(normalized.matrix, normalized.options, true)
	if Err.is_error(d):
		return d
	# Check PNG integer fields and scanline size before any pixel allocation.
	if d < 1 or d > 0xffffffff or (4 * d + 1) * d > 0xffffffff:
		return Err.error("INVALID_INPUT", "PNG geometry exceeds uint32 bound")
	var image = to_pixels(normalized.matrix, normalized.options)
	if Err.is_error(image):
		return image
	var stride = 4 * d
	var raw = PackedByteArray()
	for y in range(d):
		raw.append(0)
		raw.append_array(image.pixels.slice(y * stride, (y + 1) * stride))
	var compressed = PackedByteArray([0x78, 0x01])
	var pos = 0
	while pos < raw.size():
		var n = mini(65535, raw.size() - pos)
		var inverse = n ^ 65535
		compressed.append_array(PackedByteArray([1 if pos + n == raw.size() else 0, n & 255, (n >> 8) & 255, inverse & 255, (inverse >> 8) & 255]))
		compressed.append_array(raw.slice(pos, pos + n))
		pos += n
	compressed.append_array(_u32(_adler32(raw)))
	var ihdr = _u32(d)
	ihdr.append_array(_u32(d))
	ihdr.append_array(PackedByteArray([8, 6, 0, 0, 0]))
	var out = PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	out.append_array(_chunk("IHDR", ihdr))
	out.append_array(_chunk("IDAT", compressed))
	out.append_array(_chunk("IEND", PackedByteArray()))
	return out

static func to_svg_data_url(arg, options = null):
	var svg = to_svg(arg, options)
	if Err.is_error(svg):
		return svg
	if svg.length() > int((DATA_URL_CHARACTER_BUDGET - 31) / 3):
		return Err.error("INVALID_INPUT", "SVG URL exceeds budget")
	var pieces = PackedStringArray(["data:image/svg+xml;charset=utf-8,"])
	for byte in svg.to_ascii_buffer():
		var safe = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or [126, 33, 42, 39, 40, 41, 46, 95, 45].has(byte)
		pieces.append(String.chr(byte) if safe else "%%%02X" % byte)
	return "".join(pieces)

static func to_png_data_url(arg, options = null):
	var png = to_png(arg, options)
	if Err.is_error(png):
		return png
	if int((png.size() + 2) / 3) * 4 + 22 > DATA_URL_CHARACTER_BUDGET:
		return Err.error("INVALID_INPUT", "PNG URL exceeds budget")
	return "data:image/png;base64," + Marshalls.raw_to_base64(png)

static func render_dimensions(arg, raw = null, dpi = null):
	var normalized = _matrix(arg, raw)
	if Err.is_error(normalized):
		return normalized
	var opts = normalized.options
	var d = _geometry(normalized.matrix, opts, false)
	if Err.is_error(d):
		return d
	var out = {"width": d, "height": d, "modulePixels": opts.scale, "marginModules": opts.margin, "dpi": dpi, "moduleSizeMm": null, "symbolSizeMm": null}
	if dpi != null:
		if not Err.is_number(dpi) or dpi <= 0:
			return Err.error("INVALID_INPUT", "DPI must be numeric, finite and positive")
		var mm = float(opts.scale) / dpi * 25.4
		var symbol = float(d) / dpi * 25.4
		if not is_finite(mm) or not is_finite(symbol) or mm <= 0 or symbol <= 0:
			return Err.error("INVALID_INPUT", "Print geometry must be finite and positive")
		out.moduleSizeMm = mm
		out.symbolSizeMm = symbol
	return out

static func to_image(arg, options = null):
	var result = to_pixels(arg, options)
	if Err.is_error(result):
		return result
	return Image.create_from_data(result.width, result.height, false, Image.FORMAT_RGBA8, result.pixels)

