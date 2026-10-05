extends SceneTree
const Render = preload("../addons/specqr/render.gd")
const Err = preload("../addons/specqr/error.gd")
var failures = []
var checks = 0
func check(condition):
	checks += 1
	if not condition: failures.append(checks)
func _init():
	var matrix = []
	for y in range(21):
		var row = []
		for x in range(21):
			row.append((x + y) % 2)
		matrix.append(row)
	var before = Time.get_ticks_msec()
	var pixels = Render.to_pixels(matrix, {"margin": 1013, "scale": 1})
	check(not Err.is_error(pixels) and pixels.width == 2047 and pixels.pixels.size() == 2047 * 2047 * 4)
	var png = Render.to_png(matrix, {"margin": 1013, "scale": 1})
	check(not Err.is_error(png))
	var native = Image.new()
	check(native.load_png_from_buffer(png) == OK)
	native.convert(Image.FORMAT_RGBA8)
	check(native.get_data() == pixels.pixels)
	check(Err.is_error(Render.to_pixels(matrix, {"margin": 1014, "scale": 1})))
	check(Err.is_error(Render.to_png(matrix, {"margin": 1014, "scale": 1})))
	check(Err.is_error(Render.to_png(matrix, {"margin": 9223372036854775807, "scale": 9223372036854775807})))
	check(Err.is_error(Render.to_png(matrix, {"scale": 4294967296})))
	check(Err.is_error(Render.render_dimensions(matrix, {"scale": 1000000000}, 0.0000001)))
	print(JSON.stringify({"checks": checks, "failures": failures, "maxPixels": 2047 * 2047, "pngBytes": png.size(), "elapsedMs": Time.get_ticks_msec() - before}))
	quit(0 if failures.is_empty() else 1)
