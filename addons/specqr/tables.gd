extends RefCounted
## ISO/IEC 18004 QR Model 2 version and error-correction tables.
const E = preload("error.gd")
const ERROR_CORRECTION_LEVELS = ["L", "M", "Q", "H"]
const ECC_CODEWORDS_PER_BLOCK = [

[7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
  [13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
  [17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
]
const NUM_ERROR_CORRECTION_BLOCKS = [

[1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
  [1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
  [1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
  [1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
]

static func validate_version(value):
	return null if E.in_range(value, 1, 40) else E.error("INVALID_VERSION", "QR version must be an integer in 1..40")

static func level_index(value):
	if typeof(value) != TYPE_STRING or not value in ERROR_CORRECTION_LEVELS:
		return E.error("INVALID_ECC_LEVEL", "ECC must be L, M, Q, or H")
	return ERROR_CORRECTION_LEVELS.find(value)

static func format_bits(level):
	var i = level_index(level)
	return i if E.is_error(i) else [1, 0, 3, 2][i]

static func qr_size(version):
	var checked = validate_version(version)
	return checked if E.is_error(checked) else 4 * int(version) + 17

static func raw_codeword_count(version):
	var checked = validate_version(version)
	if E.is_error(checked): return checked
	var v = int(version)
	var result = (16 * v + 128) * v + 64
	if v >= 2:
		var n = int(v / 7) + 2
		result -= (25 * n - 10) * n - 55
		if v >= 7: result -= 36
	return int(result / 8)

static func block_info(version, level):
	var checked = validate_version(version)
	if E.is_error(checked): return checked
	var i = level_index(level)
	if E.is_error(i): return i
	var v = int(version)
	var blocks = NUM_ERROR_CORRECTION_BLOCKS[i][v - 1]
	var ecc = ECC_CODEWORDS_PER_BLOCK[i][v - 1]
	var raw = raw_codeword_count(v)
	return {"blocks": blocks, "eccPerBlock": ecc, "rawCodewords": raw, "dataCodewords": raw - blocks * ecc}

static func data_codeword_count(version, level):
	var info = block_info(version, level)
	return info if E.is_error(info) else info.dataCodewords

static func alignment_positions(version):
	var checked = validate_version(version)
	if E.is_error(checked): return checked
	var v = int(version)
	if v == 1: return []
	var n = int(v / 7) + 2
	var den = n * 2 - 2
	var step = 26 if v == 32 else int((v * 4 + 4 + den - 1) / den) * 2
	var result = [6]
	for i in range(n - 2, -1, -1):
		result.append(qr_size(v) - 7 - i * step)
	return result

static func character_count_bits(version, mode):
	var checked = validate_version(version)
	if E.is_error(checked): return checked
	var widths = {"numeric": [10, 12, 14], "alphanumeric": [9, 11, 13], "byte": [8, 16, 16], "kanji": [8, 10, 12]}
	if typeof(mode) != TYPE_STRING or not widths.has(mode):
		return E.error("INVALID_MODE", "Expected a data mode")
	return widths[mode][0 if version <= 9 else 1 if version <= 26 else 2]
