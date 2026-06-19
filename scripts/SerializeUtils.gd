class_name SerializeUtils

## DEFLATE + base64 (de)serialization of a JSON dictionary, shared by save-data
## export/import and level export/import (mirrors the other static-helper utils).

## Dictionary -> compact base64 string (JSON -> UTF-8 -> DEFLATE -> base64).
static func encode_dict(data: Dictionary) -> String:
	var bytes = JSON.stringify(data).to_utf8_buffer()
	var compressed = bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(compressed)

## Inverse of encode_dict. Returns {} on any failure (bad base64, undecompressable,
## or JSON that isn't a dictionary) so callers can treat is_empty() as "invalid".
static func decode_to_dict(encoded: String) -> Dictionary:
	var compressed = Marshalls.base64_to_raw(encoded)
	var decompressed = compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
	if decompressed.size() == 0:
		return {}
	var data = JSON.parse_string(decompressed.get_string_from_utf8())
	if not data is Dictionary:
		return {}
	return data
