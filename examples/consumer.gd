extends SceneTree
const QR = preload("../addons/specqr/specqr.gd")
func _initialize():
	var qr = QR.generate("こんにちは SpecQR", {"eci": true})
	if QR.is_error(qr):
		printerr(qr.code + ": " + qr.message)
		quit(1)
		return
	print("Version %d, %d modules, mask %d" % [qr.version, QR.size(qr), qr.maskPattern])
	var file = FileAccess.open("user://specqr.png", FileAccess.WRITE)
	if file == null:
		printerr("Cannot open user://specqr.png")
		quit(2)
		return
	var png = QR.to_png(qr)
	if QR.is_error(png):
		printerr(png.code + ": " + png.message)
		quit(2)
		return
	file.store_buffer(png)
	file.close()
	quit()
