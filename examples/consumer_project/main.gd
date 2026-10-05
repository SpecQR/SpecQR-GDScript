extends Node2D
## Copy addons/specqr into this fresh project, import, then run the scene.
const QR = preload("res://addons/specqr/specqr.gd")
var failures = []
var checks = 0

func check(condition, label):
	checks += 1
	if not condition: failures.append(label)

func _ready():
	var symbol = QR.generate("漢字 SpecQR 🙂", {"eci": true, "errorCorrectionLevel": "Q"})
	check(not QR.is_error(symbol), "Unicode QR generation")
	if QR.is_error(symbol): _finish(); return
	check(QR.size(symbol) == symbol.matrix.size(), "Public matrix size")
	check(QR.module_at(symbol, 0, 0) == 1, "Public finder module")
	var bytes = QR.to_png(symbol)
	check(not QR.is_error(bytes), "Scratch PNG generation")
	var expected = QR.to_pixels(symbol)
	check(not QR.is_error(expected), "RGBA generation")
	var decoded = Image.new()
	check(decoded.load_png_from_buffer(bytes) == OK, "Godot decodes generated PNG")
	decoded.convert(Image.FORMAT_RGBA8)
	check(decoded.get_width() == expected.width and decoded.get_height() == expected.height, "PNG dimensions")
	check(decoded.get_data() == expected.pixels, "Every PNG RGBA pixel")
	var native = QR.to_image(symbol)
	check(native is Image, "Native Image adapter")
	check(native.get_data() == expected.pixels, "Every native Image RGBA pixel")
	check(native.get_format() == Image.FORMAT_RGBA8, "Native image format")
	var binary = QR.generate(PackedByteArray([0, 255, 128, 1, 0]), {"version": 1, "errorCorrectionLevel": "L"})
	check(not QR.is_error(binary), "Binary NUL is lossless")
	check(QR.logical_bytes(binary.segments[0]) == [0, 255, 128, 1, 0], "Binary ownership/content")
	var plan = QR.plan("12345678901234567890")
	check(not QR.is_error(plan) and plan.ok and not plan.diagnostics.codewords_built, "Arithmetic-only planner")
	var elements = [{"ai": "01", "value": "09506000134352"}, {"ai": "10", "value": "LOT1"}]
	var gs1 = QR.generate(QR.create_gs1_element_string(elements), {"gs1": true})
	check(not QR.is_error(gs1) and gs1.diagnostics.gs1_validation.enabled, "GS1 validation")
	var set = QR.generate_structured_append("x".repeat(100), {"version": 1, "errorCorrectionLevel": "L"})
	check(not QR.is_error(set) and set.total >= 2, "Structured Append")
	var image_path = OS.get_environment("SPECQR_CONSUMER_PNG")
	if image_path != "":
		var output = FileAccess.open(image_path, FileAccess.WRITE)
		check(output != null, "Consumer PNG output opened")
		if output != null:
			output.store_buffer(bytes)
			output.close()
	_finish()

func _finish():
	var report = {"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures, "godot": Engine.get_version_info().string, "renderer": DisplayServer.get_name(), "imagePixelsMatched": failures.is_empty(), "gpuTextureTested": false}
	var report_path = OS.get_environment("SPECQR_CONSUMER_REPORT")
	if report_path != "":
		var file = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null: get_tree().quit(2); return
		file.store_string(JSON.stringify(report) + "\n")
		file.close()
	else: print(JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
