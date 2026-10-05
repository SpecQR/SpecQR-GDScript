extends SceneTree
const Render = preload("../addons/specqr/render.gd")
const Err = preload("../addons/specqr/error.gd")
var checks = 0
var failures = []

func _check(ok, label):
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: " + label)

func _hash(bytes):
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _matrix(n, pattern):
	var out = []
	for y in range(n):
		var row = []
		for x in range(n):
			row.append((x + y) % 2 == 0 if pattern == 0 else ((x * 3 + y * 7) % 11) < 5 if pattern == 1 else x == y or x + y == n - 1)
		out.append(row)
	return out

func _init():
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/render_expected.json"))
	for index in range(fixture.cases.size()):
		var test = fixture.cases[index]
		var matrix = _matrix(int(test.size), int(test.pattern))
		var pixels = Render.to_pixels(matrix, test.options)
		_check(not Err.is_error(pixels), "pixels success %d" % index)
		if Err.is_error(pixels):
			continue
		_check(pixels.width == test.width and pixels.height == test.width, "dimensions %d" % index)
		_check(pixels.pixels.size() == test.pixelsSize and _hash(pixels.pixels) == test.pixelsSha256, "pixel parity %d" % index)
		var png = Render.to_png(matrix, test.options)
		_check(not Err.is_error(png) and png.size() == test.pngSize and _hash(png) == test.pngSha256, "PNG byte parity %d" % index)
		var svg = Render.to_svg(matrix, test.options)
		_check(not Err.is_error(svg) and svg.length() == test.svgSize and svg.sha256_text() == test.svgSha256, "SVG parity %d" % index)
		_check(Render.to_png_data_url(matrix, test.options).sha256_text() == test.pngUrlSha256, "PNG URL parity %d" % index)
		_check(Render.to_svg_data_url(matrix, test.options).sha256_text() == test.svgUrlSha256, "SVG URL parity %d" % index)
		var decoded = Image.new()
		_check(decoded.load_png_from_buffer(png) == OK, "native PNG decoder %d" % index)
		decoded.convert(Image.FORMAT_RGBA8)
		_check(decoded.get_data() == pixels.pixels, "native PNG exact pixels %d" % index)
		var native = Render.to_image(matrix, test.options)
		_check(native is Image and native.get_data() == pixels.pixels, "Image adapter %d" % index)
	var matrix = _matrix(21, 0)
	for invalid_bool in [0, 1, 1.0, "yes", [], {}, null]:
		_check(Err.is_error(Render.parse_color("red", invalid_bool)), "strict boolean type")
		_check(Err.is_error(Render.geometry(matrix, null, invalid_bool)), "raster boolean type")
	_check(Render.parse_color("#abc") == [170, 187, 204, 255], "short RGB")
	_check(Render.parse_color("#abcd") == [170, 187, 204, 221], "short RGBA")
	_check(Render.parse_color("#01234567") == [1, 35, 69, 103], "long RGBA")
	_check(Render.parse_color(" navy ", false) == null, "CSS name SVG only")
	_check(Render.contrast_ratio([0,0,0,255], [255,255,255,255]) == 21.0, "contrast 21")
	_check(abs(Render.render_dimensions(matrix, null, 300).moduleSizeMm - 8.0 / 300 * 25.4) < 1e-12, "DPI 300")
	for value in ["", "red\"/>", "url(x)", "#ab", "#ggg", "rgb(0,0,0)", "a".repeat(65), 1, [], {}, true, null]:
		_check(Err.is_error(Render.parse_color(value)), "invalid color " + str(value))
	for opts in [{"scale": 0}, {"scale": 1000000001}, {"margin": -1}, {"margin": 1000000000}, {"scale": "8"}, {"scale": []}, {"bogus": 1}, {"scale": 71, "margin": 4}, {"scale": INF}, {"scale": NAN}]:
		_check(Err.is_error(Render.to_png(matrix, opts)), "invalid render " + str(opts))
	for dpi in [0, -1, INF, NAN, 1e-308, "300", []]:
		_check(Err.is_error(Render.render_dimensions(matrix, null, dpi)), "invalid DPI " + str(dpi))
	for bad in [null, {}, [], [[true]], 1, true]:
		_check(Err.is_error(Render.to_svg(bad)), "invalid matrix " + str(bad))
	for bit in [2, -1, "1", 0.5, NAN, INF, null, {}]:
		var changed = matrix.duplicate(true)
		changed[0][0] = bit
		_check(Err.is_error(Render.to_svg(changed)), "invalid matrix module " + str(bit))
	for bit in [0, 1, 0.0, 1.0, true, false]:
		var changed = matrix.duplicate(true)
		changed[0][0] = bit
		_check(not Err.is_error(Render.to_svg(changed)), "valid matrix module " + str(bit))
	_check(Err.is_error(Render.to_pixels(matrix, {"foreground": "navy"})), "raster CSS name rejection")
	_check(not Err.is_error(Render.to_svg(matrix, {"foreground": "navy"})), "SVG CSS name accepted")
	_check(Render._crc32("123456789".to_ascii_buffer()) == 0xcbf43926, "CRC32 standard vector")
	_check(Render._adler32("Wikipedia".to_ascii_buffer()) == 0x11e60398, "Adler32 standard vector")
	print(JSON.stringify({"checks": checks, "failed": failures.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
