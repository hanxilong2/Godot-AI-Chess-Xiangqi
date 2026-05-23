extends RefCounted
class_name XiangqiRules

const NativeRulesScript := preload("res://resource/xiangqi/src/XiangqiRulesNative.cs")
const NATIVE_RULES_CPP_CLASS := &"XiangqiRulesNativeCpp"

const ORTHOGONAL_DIRECTIONS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

const ADVISOR_DIRECTIONS := [
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

const ELEPHANT_DIRECTIONS := [
	{"move": Vector2i(2, 2), "eye": Vector2i(1, 1)},
	{"move": Vector2i(2, -2), "eye": Vector2i(1, -1)},
	{"move": Vector2i(-2, 2), "eye": Vector2i(-1, 1)},
	{"move": Vector2i(-2, -2), "eye": Vector2i(-1, -1)},
]

const HORSE_DIRECTIONS := [
	{"move": Vector2i(1, 2), "leg": Vector2i(0, 1)},
	{"move": Vector2i(-1, 2), "leg": Vector2i(0, 1)},
	{"move": Vector2i(1, -2), "leg": Vector2i(0, -1)},
	{"move": Vector2i(-1, -2), "leg": Vector2i(0, -1)},
	{"move": Vector2i(2, 1), "leg": Vector2i(1, 0)},
	{"move": Vector2i(2, -1), "leg": Vector2i(1, 0)},
	{"move": Vector2i(-2, 1), "leg": Vector2i(-1, 0)},
	{"move": Vector2i(-2, -1), "leg": Vector2i(-1, 0)},
]

static var _native_rules: RefCounted = null

static func implementation_stage() -> int:
	var native := _get_native_rules()
	if native != null and native.has_method("implementation_stage"):
		return int(native.call("implementation_stage"))
	return 2

static func rules_ready() -> bool:
	var native := _get_native_rules()
	if native != null and native.has_method("rules_ready"):
		return bool(native.call("rules_ready"))
	return true

static func generate_pseudo_legal_moves(state: XiangqiState, from_index: int = -1) -> Array:
	if state == null:
		return []
	var native := _get_native_rules()
	if native != null and native.has_method("generate_pseudo_legal_moves"):
		return _decode_native_moves(native.call("generate_pseudo_legal_moves", _rules_state(state), from_index))
	return generate_pseudo_legal_moves_for_side(state, state.side_to_move, from_index)

static func generate_pseudo_legal_moves_for_side(state: XiangqiState, side: int, from_index: int = -1) -> Array:
	if state == null:
		return []
	var native := _get_native_rules()
	if native != null and native.has_method("generate_pseudo_legal_moves_for_side"):
		return _decode_native_moves(native.call("generate_pseudo_legal_moves_for_side", _rules_state(state), side, from_index))

	var moves: Array = []
	if from_index != -1:
		if !_owns_piece(state, from_index, side):
			return []
		_append_piece_moves(state, from_index, moves)
		return moves

	for index in state.get_indices_for_side(side):
		_append_piece_moves(state, int(index), moves)
	return moves

static func generate_legal_moves(state: XiangqiState, side: int = -1, from_index: int = -1) -> Array:
	if state == null:
		return []

	var resolved_side := _resolve_side(state, side)
	var native := _get_native_rules()
	if native != null and native.has_method("generate_legal_moves"):
		return _decode_native_moves(native.call("generate_legal_moves", _rules_state(state), resolved_side, from_index))

	var legal_moves: Array = []
	var candidates := generate_pseudo_legal_moves_for_side(state, resolved_side, from_index)
	for candidate in candidates:
		if !_is_move_legal_on_board(state, candidate, resolved_side):
			continue
		var move: XiangqiMove = candidate.duplicate()
		var preview_state := state.duplicate()
		preview_state.apply_move(move)
		var opponent := XiangqiConstants.other_side(resolved_side)
		if is_in_check(preview_state, opponent):
			move.flags |= XiangqiConstants.FLAG_CHECK
		if !has_any_legal_move(preview_state, opponent):
			move.flags |= XiangqiConstants.FLAG_CHECKMATE
		legal_moves.push_back(move)
	return legal_moves

static func is_legal_move(state: XiangqiState, move: XiangqiMove, side: int = -1) -> bool:
	if state == null or move == null or !move.is_valid():
		return false

	var resolved_side := _resolve_side(state, side)
	var native := _get_native_rules()
	if native != null and native.has_method("is_legal_move"):
		return bool(native.call("is_legal_move", _rules_state(state), move, resolved_side))

	if !_owns_piece(state, move.from_index, resolved_side):
		return false

	for legal_move in generate_legal_moves(state, resolved_side, move.from_index):
		if legal_move.from_index == move.from_index and legal_move.to_index == move.to_index:
			return true
	return false

static func is_in_check(state: XiangqiState, side: int) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native != null and native.has_method("is_in_check"):
		return bool(native.call("is_in_check", _rules_state(state), side))

	var general_index := state.find_general(side)
	if general_index == -1:
		return true
	return _is_square_attacked(state, general_index, XiangqiConstants.other_side(side))

static func are_generals_facing(state: XiangqiState) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native != null and native.has_method("are_generals_facing"):
		return bool(native.call("are_generals_facing", _rules_state(state)))

	var red_general := state.find_general(XiangqiConstants.RED)
	var black_general := state.find_general(XiangqiConstants.BLACK)
	if red_general == -1 or black_general == -1:
		return false

	var red_coord := XiangqiCoord.from_index(red_general)
	var black_coord := XiangqiCoord.from_index(black_general)
	if red_coord.x != black_coord.x:
		return false

	return _count_pieces_between_on_file(state, red_coord.x, red_coord.y, black_coord.y) == 0

static func has_any_legal_move(state: XiangqiState, side: int = -1, from_index: int = -1) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native != null and native.has_method("has_any_legal_move"):
		return bool(native.call("has_any_legal_move", _rules_state(state), _resolve_side(state, side), from_index))
	return !generate_legal_moves(state, side, from_index).is_empty()

static func is_checkmate(state: XiangqiState, side: int = -1) -> bool:
	if state == null:
		return false
	var resolved_side := _resolve_side(state, side)
	var native := _get_native_rules()
	if native != null and native.has_method("is_checkmate"):
		return bool(native.call("is_checkmate", _rules_state(state), resolved_side))
	return !has_any_legal_move(state, resolved_side)

static func is_stalemate(state: XiangqiState, side: int = -1) -> bool:
	if state == null:
		return false
	var resolved_side := _resolve_side(state, side)
	var native := _get_native_rules()
	if native != null and native.has_method("is_stalemate"):
		return bool(native.call("is_stalemate", _rules_state(state), resolved_side))
	return false

static func get_position_status(state: XiangqiState, side: int = -1) -> String:
	if state == null:
		return "invalid"

	var resolved_side := _resolve_side(state, side)
	var native := _get_native_rules()
	if native != null and native.has_method("get_position_status"):
		return String(native.call("get_position_status", _rules_state(state), resolved_side))

	var in_check := is_in_check(state, resolved_side)
	var has_move := has_any_legal_move(state, resolved_side)
	if !has_move:
		return "checkmate"
	if in_check:
		return "check"
	return "ok"

static func get_status_text() -> String:
	return "Local rules ready (Stage 2)."

static func _get_native_rules() -> RefCounted:
	if _native_rules == null:
		if ClassDB.class_exists(NATIVE_RULES_CPP_CLASS):
			_native_rules = ClassDB.instantiate(NATIVE_RULES_CPP_CLASS) as RefCounted
		if _native_rules == null:
			_native_rules = NativeRulesScript.new()
	return _native_rules

static func _rules_state(state: XiangqiState) -> Variant:
	if state == null:
		return null
	return state.native_state if state.native_state != null else state

static func _decode_native_moves(encoded_variant: Variant) -> Array:
	var encoded := PackedInt32Array(encoded_variant)
	var moves: Array = []
	var read_index := 0
	while read_index + 4 < encoded.size():
		var piece_code := int(encoded[read_index + 2])
		var captured_code := int(encoded[read_index + 3])
		moves.push_back(XiangqiMove.new(
			int(encoded[read_index]),
			int(encoded[read_index + 1]),
			String.chr(piece_code) if piece_code != 0 else "",
			String.chr(captured_code) if captured_code != 0 else "",
			int(encoded[read_index + 4])
		))
		read_index += 5
	return moves

static func _resolve_side(state: XiangqiState, side: int) -> int:
	return state.side_to_move if side == -1 else side

static func _append_piece_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var piece := state.get_piece_at(from_index)
	if piece.is_empty():
		return

	match XiangqiConstants.piece_type(piece):
		"r":
			_generate_rook_moves(state, from_index, moves)
		"c":
			_generate_cannon_moves(state, from_index, moves)
		"h":
			_generate_horse_moves(state, from_index, moves)
		"e":
			_generate_elephant_moves(state, from_index, moves)
		"a":
			_generate_advisor_moves(state, from_index, moves)
		"k":
			_generate_general_moves(state, from_index, moves)
		"p":
			_generate_soldier_moves(state, from_index, moves)

static func _generate_rook_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	for direction_value in ORTHOGONAL_DIRECTIONS:
		var direction: Vector2i = direction_value
		var next_file: int = coord.x + direction.x
		var next_rank: int = coord.y + direction.y
		while XiangqiCoord.is_valid(next_file, next_rank):
			var to_index: int = XiangqiCoord.to_index(next_file, next_rank)
			if state.is_empty_at(to_index):
				_append_move(state, moves, from_index, to_index)
			else:
				_append_move(state, moves, from_index, to_index)
				break
			next_file += direction.x
			next_rank += direction.y

static func _generate_cannon_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	for direction_value in ORTHOGONAL_DIRECTIONS:
		var direction: Vector2i = direction_value
		var next_file: int = coord.x + direction.x
		var next_rank: int = coord.y + direction.y
		var screen_found: bool = false
		while XiangqiCoord.is_valid(next_file, next_rank):
			var to_index: int = XiangqiCoord.to_index(next_file, next_rank)
			if !screen_found:
				if state.is_empty_at(to_index):
					_append_move(state, moves, from_index, to_index)
				else:
					screen_found = true
			else:
				if !state.is_empty_at(to_index):
					_append_move(state, moves, from_index, to_index)
					break
			next_file += direction.x
			next_rank += direction.y

static func _generate_horse_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	for pattern_value in HORSE_DIRECTIONS:
		var pattern: Dictionary = pattern_value
		var leg: Vector2i = pattern["leg"]
		var leg_file: int = coord.x + leg.x
		var leg_rank: int = coord.y + leg.y
		if !XiangqiCoord.is_valid(leg_file, leg_rank):
			continue
		if !state.is_empty_at(XiangqiCoord.to_index(leg_file, leg_rank)):
			continue

		var move_offset: Vector2i = pattern["move"]
		var target_file: int = coord.x + move_offset.x
		var target_rank: int = coord.y + move_offset.y
		if !XiangqiCoord.is_valid(target_file, target_rank):
			continue
		_append_move(state, moves, from_index, XiangqiCoord.to_index(target_file, target_rank))

static func _generate_elephant_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var piece: String = state.get_piece_at(from_index)
	var side: int = XiangqiConstants.side_from_piece(piece)
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	for pattern_value in ELEPHANT_DIRECTIONS:
		var pattern: Dictionary = pattern_value
		var eye: Vector2i = pattern["eye"]
		var eye_file: int = coord.x + eye.x
		var eye_rank: int = coord.y + eye.y
		if !XiangqiCoord.is_valid(eye_file, eye_rank):
			continue
		if !state.is_empty_at(XiangqiCoord.to_index(eye_file, eye_rank)):
			continue

		var move_offset: Vector2i = pattern["move"]
		var target_file: int = coord.x + move_offset.x
		var target_rank: int = coord.y + move_offset.y
		if !XiangqiCoord.is_valid(target_file, target_rank):
			continue
		if XiangqiConstants.has_crossed_river(side, target_rank):
			continue
		_append_move(state, moves, from_index, XiangqiCoord.to_index(target_file, target_rank))

static func _generate_advisor_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var piece: String = state.get_piece_at(from_index)
	var side: int = XiangqiConstants.side_from_piece(piece)
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	for direction_value in ADVISOR_DIRECTIONS:
		var direction: Vector2i = direction_value
		var target_file: int = coord.x + direction.x
		var target_rank: int = coord.y + direction.y
		if !XiangqiCoord.is_valid(target_file, target_rank):
			continue
		if !XiangqiConstants.is_in_palace(side, target_file, target_rank):
			continue
		_append_move(state, moves, from_index, XiangqiCoord.to_index(target_file, target_rank))

static func _generate_general_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var piece: String = state.get_piece_at(from_index)
	var side: int = XiangqiConstants.side_from_piece(piece)
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	for direction_value in ORTHOGONAL_DIRECTIONS:
		var direction: Vector2i = direction_value
		var target_file: int = coord.x + direction.x
		var target_rank: int = coord.y + direction.y
		if !XiangqiCoord.is_valid(target_file, target_rank):
			continue
		if !XiangqiConstants.is_in_palace(side, target_file, target_rank):
			continue
		_append_move(state, moves, from_index, XiangqiCoord.to_index(target_file, target_rank))

	var enemy_general_index: int = state.find_general(XiangqiConstants.other_side(side))
	if enemy_general_index == -1:
		return
	var enemy_coord: Vector2i = XiangqiCoord.from_index(enemy_general_index)
	if enemy_coord.x != coord.x:
		return
	if _count_pieces_between_on_file(state, coord.x, coord.y, enemy_coord.y) == 0:
		_append_move(state, moves, from_index, enemy_general_index, XiangqiConstants.FLAG_SPECIAL)

static func _generate_soldier_moves(state: XiangqiState, from_index: int, moves: Array) -> void:
	var piece: String = state.get_piece_at(from_index)
	var side: int = XiangqiConstants.side_from_piece(piece)
	var coord: Vector2i = XiangqiCoord.from_index(from_index)
	var forward: int = -1 if side == XiangqiConstants.RED else 1

	var forward_rank: int = coord.y + forward
	if XiangqiCoord.is_valid(coord.x, forward_rank):
		_append_move(state, moves, from_index, XiangqiCoord.to_index(coord.x, forward_rank))

	if !XiangqiConstants.has_crossed_river(side, coord.y):
		return

	for file_offset_value in [-1, 1]:
		var file_offset: int = file_offset_value
		var target_file: int = coord.x + file_offset
		if !XiangqiCoord.is_valid(target_file, coord.y):
			continue
		_append_move(state, moves, from_index, XiangqiCoord.to_index(target_file, coord.y))

static func _append_move(state: XiangqiState, moves: Array, from_index: int, to_index: int, extra_flags: int = 0) -> void:
	if !XiangqiCoord.is_valid_index(from_index) or !XiangqiCoord.is_valid_index(to_index):
		return

	var piece := state.get_piece_at(from_index)
	if piece.is_empty():
		return

	var side := XiangqiConstants.side_from_piece(piece)
	var captured_piece := state.get_piece_at(to_index)
	if !captured_piece.is_empty() and XiangqiConstants.side_from_piece(captured_piece) == side:
		return

	var flags := extra_flags
	if !captured_piece.is_empty():
		flags |= XiangqiConstants.FLAG_CAPTURE
	moves.push_back(XiangqiMove.new(from_index, to_index, piece, captured_piece, flags))

static func _is_square_attacked(state: XiangqiState, square_index: int, attacker_side: int) -> bool:
	for index in state.get_indices_for_side(attacker_side):
		var attack_moves: Array = []
		_append_piece_moves(state, int(index), attack_moves)
		for move in attack_moves:
			if move.to_index == square_index:
				return true
	return false

static func _is_move_legal_on_board(state: XiangqiState, move: XiangqiMove, side: int) -> bool:
	var preview_state := state.duplicate()
	preview_state.apply_move(move)
	if are_generals_facing(preview_state):
		return false
	return !is_in_check(preview_state, side)

static func _owns_piece(state: XiangqiState, index: int, side: int) -> bool:
	var piece := state.get_piece_at(index)
	return !piece.is_empty() and XiangqiConstants.side_from_piece(piece) == side

static func _count_pieces_between_on_file(state: XiangqiState, file: int, rank_a: int, rank_b: int) -> int:
	if rank_a == rank_b:
		return 0
	var count: int = 0
	var start_rank: int = mini(rank_a, rank_b) + 1
	var end_rank: int = maxi(rank_a, rank_b)
	for rank in range(start_rank, end_rank):
		if !state.is_empty_at(XiangqiCoord.to_index(file, rank)):
			count += 1
	return count
