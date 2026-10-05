class_name SpecQR
extends RefCounted
## Dependency-free QR Model 2 for the standard Godot engine.
## Expected failures return a SpecQRError dictionary; check is_error(result).
const VERSION = "0.1.0"
const Error = preload("error.gd")
const Core = preload("core.gd")
const Tables = preload("tables.gd")
const Optimizer = preload("optimizer.gd")
const API = preload("api.gd")
const Segments = preload("segments.gd")
const Render = preload("render.gd")
const GS1 = preload("gs1.gd")
const StructuredAppend = preload("structured_append.gd")

static func is_error(value):
	return Error.is_error(value)

static func normalize_options(raw=null):
	return API.normalize_options(raw)

static func validate_options(raw=null):
	return API.validate_options(raw)

static func render_options(raw=null):
	return API.render_options(raw)

static func get_capacity(version, level="M", mode="", control=0):
	return API.get_capacity(version, level, mode, control)

static func plan(value, raw=null):
	return API.plan(value, raw)

static func plan_segments(values, raw=null):
	return API.plan_segments(values, raw)

static func generate(value, raw=null):
	return API.generate(value, raw)

static func generate_segments(values, raw=null):
	return API.generate_segments(values, raw)

static func estimate(value, raw=null):
	return API.estimate(value, raw)

static func analyze_segments(values, raw=null):
	return API.analyze_segments(values, raw)

static func diagnostics(value):
	return API.diagnostics(value)

static func size(value):
	return API.size(value)

static func module_at(value, x, y):
	return API.module_at(value, x, y)

static func strict_text(value):
	return Segments.strict_text(value)

static func encode_utf8(value):
	return Segments.encode_utf8(value)

static func kanji_code(character):
	return Segments.kanji_code(character)

static func can_encode_kanji(character):
	return Segments.can_encode_kanji(character)

static func kanji_value(character):
	return Segments.kanji_value(character)

static func alpha_value(character):
	return Segments.alpha_value(character)

static func new_segment(segment_mode, value):
	return Segments.new_segment(segment_mode, value)

static func byte_segment(value):
	return Segments.byte_segment(value)

static func numeric(value):
	return Segments.numeric(value)

static func alphanumeric(value):
	return Segments.alphanumeric(value)

static func kanji(value):
	return Segments.kanji(value)

static func eci(assignment):
	return Segments.eci(assignment)

static func fnc1():
	return Segments.fnc1()

static func fnc1_second(indicator):
	return Segments.fnc1_second(indicator)

static func structured_append_segment(sequence_index, sequence_total, sequence_parity):
	return Segments.structured_append_segment(sequence_index, sequence_total, sequence_parity)

static func validate_segment(segment):
	return Segments.validate_segment(segment)

static func mode(segment):
	return Segments.mode(segment)

static func is_control(segment):
	return Segments.is_control(segment)

static func is_binary(segment):
	return Segments.is_binary(segment)

static func text(segment):
	return Segments.text(segment)

static func logical_bytes(segment):
	return Segments.logical_bytes(segment)

static func segment_count(segment):
	return Segments.segment_count(segment)

static func count(segment):
	return Segments.count(segment)

static func character_count(segment):
	return Segments.character_count(segment)

static func byte_count(segment):
	return Segments.byte_count(segment)

static func assignment_number(segment):
	return Segments.assignment_number(segment)

static func application_indicator(segment):
	return Segments.application_indicator(segment)

static func application_indicator_codeword(segment):
	return Segments.application_indicator_codeword(segment)

static func index(segment):
	return Segments.index(segment)

static func total(segment):
	return Segments.total(segment)

static func parity(segment):
	return Segments.parity(segment)

static func payload_bit_length(segment_mode, length):
	return Segments.payload_bit_length(segment_mode, length)

static func bit_length(segment, version):
	return Segments.bit_length(segment, version)

static func bits(segment, version):
	return Segments.bits(segment, version)

static func normalize_segments(values):
	return Segments.normalize_segments(values)

static func segments_bit_length(values, version):
	return Segments.segments_bit_length(values, version)

static func segments_bits(values, version):
	return Segments.segments_bits(values, version)

static func decode_utf8(bytes):
	return Segments.decode_utf8(bytes)

static func color_text(value):
	return Render.color_text(value)

static func parse_color(value, strict = true):
	return Render.parse_color(value, strict)

static func contrast_ratio(foreground, background):
	return Render.contrast_ratio(foreground, background)

static func geometry(arg, raw = null, raster = false):
	return Render.geometry(arg, raw, raster)

static func to_svg(arg, raw = null):
	return Render.to_svg(arg, raw)

static func to_pixels(arg, raw = null):
	return Render.to_pixels(arg, raw)

static func to_png(arg, options = null):
	return Render.to_png(arg, options)

static func to_svg_data_url(arg, options = null):
	return Render.to_svg_data_url(arg, options)

static func to_png_data_url(arg, options = null):
	return Render.to_png_data_url(arg, options)

static func render_dimensions(arg, raw = null, dpi = null):
	return Render.render_dimensions(arg, raw, dpi)

static func to_image(arg, options = null):
	return Render.to_image(arg, options)


static func get_supported_gs1_ais():
	return GS1.get_supported_gs1_ais()

static func get_gs1_ai_info(input):
	return GS1.get_gs1_ai_info(input)

static func calculate_gs1_check_digit(input):
	return GS1.calculate_gs1_check_digit(input)

static func validate_gs1_check_digit(input):
	return GS1.validate_gs1_check_digit(input)

static func calculate_gtin_check_digit(input):
	return GS1.calculate_gtin_check_digit(input)

static func append_gtin_check_digit(input):
	return GS1.append_gtin_check_digit(input)

static func validate_gtin_check_digit(input):
	return GS1.validate_gtin_check_digit(input)

static func calculate_sscc_check_digit(input):
	return GS1.calculate_sscc_check_digit(input)

static func append_sscc_check_digit(input):
	return GS1.append_sscc_check_digit(input)

static func validate_sscc_check_digit(input):
	return GS1.validate_sscc_check_digit(input)

static func normalize_gs1_elements(input):
	return GS1.normalize_gs1_elements(input)

static func parse_gs1_human_readable(input):
	return GS1.parse_gs1_human_readable(input)

static func parse_gs1_element_string(input):
	return GS1.parse_gs1_element_string(input)

static func create_gs1_element_string(input):
	return GS1.create_gs1_element_string(input)

static func gs1_to_human_readable(input):
	return GS1.gs1_to_human_readable(input)

static func gs1_element_string_to_human_readable(input):
	return GS1.gs1_element_string_to_human_readable(input)

static func validate_gs1_elements(input, options = null):
	return GS1.validate_gs1_elements(input, options)

static func validate_gs1_element_string(input, options = null):
	return GS1.validate_gs1_element_string(input, options)

static func create_gs1_digital_link(elements, options = null):
	return GS1.create_gs1_digital_link(elements, options)

static func parse_gs1_digital_link(input, options = null):
	return GS1.parse_gs1_digital_link(input, options)

static func validate_gs1_digital_link(input, options = null):
	return GS1.validate_gs1_digital_link(input, options)

static func normalize_gs1_digital_link(input, options = null):
	return GS1.normalize_gs1_digital_link(input, options)

static func gs1_normalize(input):
	return GS1.gs1_normalize(input)

static func gs1_from_human_readable(input):
	return GS1.gs1_from_human_readable(input)

static func gs1_to_element_string(input):
	return GS1.gs1_to_element_string(input)

static func gs1_build(input):
	return GS1.gs1_build(input)

static func gs1_parse(input):
	return GS1.gs1_parse(input)

static func gs1_digital_link(input, options = null):
	return GS1.gs1_digital_link(input, options)

static func gs1_to_digital_link(input, options = null):
	return GS1.gs1_to_digital_link(input, options)

static func calculate_structured_append_parity(input):
	return StructuredAppend.calculate_structured_append_parity(input)

static func calculate_structured_append_segments_parity(values):
	return StructuredAppend.calculate_structured_append_segments_parity(values)

static func generate_structured_append(input, raw=null, maximum=16, include_diagnostics=false):
	return StructuredAppend.generate_structured_append(input, raw, maximum, include_diagnostics)

static func generate_segments_structured_append(segments, raw=null, maximum=16, include_diagnostics=false, detail="summary", results=null):
	return StructuredAppend.generate_segments_structured_append(segments, raw, maximum, include_diagnostics, detail, results)

static func merge_structured_append_parts(parts):
	return StructuredAppend.merge_structured_append_parts(parts)
