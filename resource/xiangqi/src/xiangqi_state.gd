extends RefCounted
class_name XiangqiState

const NativeStateScript := preload("res://resource/xiangqi/src/XiangqiNativeState.cs")
const NATIVE_STATE_CPP_CLASS := &"XiangqiNativeStateCpp"

var native_state: RefCounted = null
var board: Array = []
var side_to_move: int = XiangqiConstants.RED
var halfmove_clock: int = 0
var fullmove_number: int = 1
var move_history: Array = []

func _init() -> void:
	clear()

func clear() -> void:
	_ensure_native_state()
	native_state.call("clear")
	_sync_mirror_from_native()
	move_history.clear()

func load_board(new_board: Array, side: int = XiangqiConstants.RED, halfmove: int = 0, fullmove: int = 1) -> void:
	_ensure_native_state()
	native_state.call("load_board", new_board, side, halfmove, fullmove)
	_sync_mirror_from_native()
	move_history.clear()

func setup_start_position() -> bool:
	return XiangqiFen.apply_to_state(self, XiangqiConstants.START_FEN)

func setup_from_fen(fen: String) -> bool:
	return XiangqiFen.apply_to_state(self, fen)

func set_side_to_move(side: int) -> void:
	_ensure_native_state()
	native_state.call("set_side_to_move", side)
	side_to_move = int(native_state.call("get_side_to_move"))

func has_piece_at(index: int) -> bool:
	_ensure_native_state()
	return bool(native_state.call("has_piece_at", index))

func is_empty_at(index: int) -> bool:
	_ensure_native_state()
	return bool(native_state.call("is_empty_at", index))

func get_piece_at(index: int) -> String:
	_ensure_native_state()
	return String(native_state.call("get_piece_at", index))

func set_piece_at(index: int, piece: String) -> void:
	if !XiangqiCoord.is_valid_index(index):
		return
	_ensure_native_state()
	native_state.call("set_piece_at", index, piece)
	board[index] = String(native_state.call("get_piece_at", index))

func remove_piece_at(index: int) -> String:
	_ensure_native_state()
	var removed := String(native_state.call("remove_piece_at", index))
	if XiangqiCoord.is_valid_index(index):
		board[index] = ""
	return removed

func apply_move(move: XiangqiMove) -> XiangqiMove:
	var applied := move.duplicate()
	if !applied.is_valid():
		return applied
	_ensure_native_state()
	var encoded := PackedInt32Array(native_state.call("apply_move", applied.from_index, applied.to_index, applied.piece, applied.flags))
	if encoded.size() < 8 or int(encoded[2]) == 0:
		return applied
	applied.piece = String.chr(int(encoded[2]))
	applied.captured_piece = String.chr(int(encoded[3])) if int(encoded[3]) != 0 else ""
	applied.flags = int(encoded[4])
	board[applied.from_index] = ""
	board[applied.to_index] = applied.piece
	move_history.push_back(applied.duplicate())
	side_to_move = int(encoded[5])
	halfmove_clock = int(encoded[6])
	fullmove_number = int(encoded[7])
	return applied

func undo_move() -> XiangqiMove:
	if move_history.is_empty():
		return XiangqiMove.new()
	_ensure_native_state()
	var last_move: XiangqiMove = move_history.pop_back()
	var encoded := PackedInt32Array(native_state.call("undo_move", last_move.from_index, last_move.to_index, last_move.piece, last_move.captured_piece, last_move.flags))
	if encoded.size() >= 8 and last_move.is_valid():
		board[last_move.from_index] = last_move.piece
		board[last_move.to_index] = last_move.captured_piece
		side_to_move = int(encoded[5])
		halfmove_clock = int(encoded[6])
		fullmove_number = int(encoded[7])
	return last_move

func find_piece(piece: String) -> int:
	_ensure_native_state()
	return int(native_state.call("find_piece", piece))

func find_general(side: int) -> int:
	_ensure_native_state()
	return int(native_state.call("find_general", side))

func get_piece_side(index: int) -> int:
	_ensure_native_state()
	return int(native_state.call("get_piece_side", index))

func get_indices_for_side(side: int) -> Array:
	_ensure_native_state()
	var packed := PackedInt32Array(native_state.call("get_indices_for_side", side))
	var indices: Array = []
	for index: int in packed:
		indices.push_back(index)
	return indices

func get_piece_count() -> int:
	_ensure_native_state()
	return int(native_state.call("get_piece_count"))

func duplicate() -> XiangqiState:
	var copy := XiangqiState.new()
	_ensure_native_state()
	copy.native_state = native_state.call("duplicate_state")
	copy._sync_mirror_from_native()
	copy.move_history.clear()
	for move in move_history:
		copy.move_history.push_back(move.duplicate())
	return copy

func to_fen() -> String:
	return XiangqiFen.to_fen(self)

func _ensure_native_state() -> void:
	if native_state == null:
		native_state = _create_native_state()

func _sync_mirror_from_native() -> void:
	_ensure_native_state()
	board = Array(native_state.call("get_board_array"))
	side_to_move = int(native_state.call("get_side_to_move"))
	halfmove_clock = int(native_state.call("get_halfmove_clock"))
	fullmove_number = int(native_state.call("get_fullmove_number"))

func _create_native_state() -> RefCounted:
	if ClassDB.class_exists(NATIVE_STATE_CPP_CLASS):
		var cpp_state := ClassDB.instantiate(NATIVE_STATE_CPP_CLASS) as RefCounted
		if cpp_state != null:
			return cpp_state
	return NativeStateScript.new()
