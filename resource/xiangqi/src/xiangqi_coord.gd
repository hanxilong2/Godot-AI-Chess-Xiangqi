extends RefCounted
class_name XiangqiCoord

static func is_valid(file: int, rank: int) -> bool:
	return file >= 0 and file < XiangqiConstants.BOARD_FILES and rank >= 0 and rank < XiangqiConstants.BOARD_RANKS

static func is_valid_index(index: int) -> bool:
	return index >= 0 and index < XiangqiConstants.BOARD_SIZE

static func to_index(file: int, rank: int) -> int:
	if !is_valid(file, rank):
		return -1
	return rank * XiangqiConstants.BOARD_FILES + file

static func from_index(index: int) -> Vector2i:
	if !is_valid_index(index):
		return Vector2i(-1, -1)
	return Vector2i(index % XiangqiConstants.BOARD_FILES, index / XiangqiConstants.BOARD_FILES)

static func to_name(file: int, rank: int) -> String:
	if !is_valid(file, rank):
		return ""
	return "%s%d" % [XiangqiConstants.FILE_NAMES[file], rank]

static func index_to_name(index: int) -> String:
	var coord := from_index(index)
	return to_name(coord.x, coord.y)

static func name_to_index(name: String) -> int:
	if name.length() < 2:
		return -1
	var file_name := name.substr(0, 1).to_lower()
	if !XiangqiConstants.FILE_NAMES.has(file_name):
		return -1
	var rank_text := name.substr(1)
	if !rank_text.is_valid_int():
		return -1
	var file := XiangqiConstants.FILE_NAMES.find(file_name)
	var rank := int(rank_text)
	return to_index(file, rank)

static func index_to_engine_square(index: int) -> String:
	return index_to_name(index)

static func engine_square_to_index(square: String) -> int:
	return name_to_index(square)

static func all_square_names() -> PackedStringArray:
	var result := PackedStringArray()
	for rank: int in XiangqiConstants.BOARD_RANKS:
		for file: int in XiangqiConstants.BOARD_FILES:
			result.append(to_name(file, rank))
	return result
