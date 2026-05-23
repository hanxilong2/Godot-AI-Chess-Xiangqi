extends RefCounted
class_name XiangqiMove

var from_index: int = -1
var to_index: int = -1
var piece: String = ""
var captured_piece: String = ""
var flags: int = 0

func _init(_from_index: int = -1, _to_index: int = -1, _piece: String = "", _captured_piece: String = "", _flags: int = 0) -> void:
	from_index = _from_index
	to_index = _to_index
	piece = _piece
	captured_piece = _captured_piece
	flags = _flags

func is_valid() -> bool:
	return XiangqiCoord.is_valid_index(from_index) and XiangqiCoord.is_valid_index(to_index)

func is_capture() -> bool:
	return !captured_piece.is_empty() or (flags & XiangqiConstants.FLAG_CAPTURE) != 0

func duplicate() -> XiangqiMove:
	return XiangqiMove.new(from_index, to_index, piece, captured_piece, flags)

func to_dict() -> Dictionary:
	return {
		"from": from_index,
		"to": to_index,
		"piece": piece,
		"captured_piece": captured_piece,
		"flags": flags,
	}

func to_coordinate_string() -> String:
	if !is_valid():
		return ""
	return XiangqiCoord.index_to_engine_square(from_index) + XiangqiCoord.index_to_engine_square(to_index)

static func from_coordinate_string(text: String, state = null) -> XiangqiMove:
	if text.length() < 4:
		return XiangqiMove.new()
	var move := XiangqiMove.new(
		XiangqiCoord.engine_square_to_index(text.substr(0, 2)),
		XiangqiCoord.engine_square_to_index(text.substr(2, 2))
	)
	if state != null and move.from_index != -1:
		move.piece = state.get_piece_at(move.from_index)
		move.captured_piece = state.get_piece_at(move.to_index)
		if !move.captured_piece.is_empty():
			move.flags |= XiangqiConstants.FLAG_CAPTURE
	return move
