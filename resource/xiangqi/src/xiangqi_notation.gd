extends RefCounted
class_name XiangqiNotation

const RED_NUMERALS := [
	"\u96f6",
	"\u4e00",
	"\u4e8c",
	"\u4e09",
	"\u56db",
	"\u4e94",
	"\u516d",
	"\u4e03",
	"\u516b",
	"\u4e5d",
]

const PIECE_LABELS := {
	"K": "\u5e05",
	"A": "\u4ed5",
	"E": "\u76f8",
	"H": "\u9a6c",
	"R": "\u8f66",
	"C": "\u70ae",
	"P": "\u5175",
	"k": "\u5c06",
	"a": "\u58eb",
	"e": "\u8c61",
	"h": "\u9a6c",
	"r": "\u8f66",
	"c": "\u70ae",
	"p": "\u5352",
}

static func move_to_coordinate(move: XiangqiMove) -> String:
	return move.to_coordinate_string()

static func coordinate_to_move(text: String, state = null) -> XiangqiMove:
	return XiangqiMove.from_coordinate_string(text, state)

static func move_to_chinese(state_before_move: XiangqiState, move: XiangqiMove) -> String:
	if state_before_move == null or move == null or !move.is_valid():
		return ""

	var piece := move.piece if !move.piece.is_empty() else state_before_move.get_piece_at(move.from_index)
	if piece.is_empty():
		return move.to_coordinate_string()

	var side := XiangqiConstants.side_from_piece(piece)
	var from_coord := XiangqiCoord.from_index(move.from_index)
	var to_coord := XiangqiCoord.from_index(move.to_index)
	return _piece_designator(state_before_move, move.from_index, piece) + _action_text(piece, side, from_coord, to_coord)

static func build_move_rows(initial_state: XiangqiState, move_history: Array) -> Array:
	var rows: Array = []
	if initial_state == null:
		return rows

	var replay_state := initial_state.duplicate()
	for ply_index: int in range(move_history.size()):
		var move := move_history[ply_index] as XiangqiMove
		if move == null:
			continue
		var notation := move_to_chinese(replay_state, move)
		var moving_side := replay_state.side_to_move
		if moving_side == XiangqiConstants.RED:
			rows.push_back({
				"move_number": rows.size() + 1,
				"red": notation,
				"black": "",
			})
		else:
			if rows.is_empty() or !String((rows[rows.size() - 1] as Dictionary).get("black", "")).is_empty():
				rows.push_back({
					"move_number": rows.size() + 1,
					"red": "",
					"black": notation,
				})
			else:
				var row := rows[rows.size() - 1] as Dictionary
				row["black"] = notation
				rows[rows.size() - 1] = row
		replay_state.apply_move(move)
	return rows

static func piece_to_display_text(piece: String) -> String:
	if piece.is_empty():
		return ""
	var side_name := "Red" if XiangqiConstants.side_from_piece(piece) == XiangqiConstants.RED else "Black"
	return "%s %s" % [side_name, XiangqiConstants.piece_name(piece)]

static func describe_turn(state: XiangqiState) -> String:
	return "Red to move" if state.side_to_move == XiangqiConstants.RED else "Black to move"

static func _piece_designator(state_before_move: XiangqiState, from_index: int, piece: String) -> String:
	var piece_label: String = String(PIECE_LABELS.get(piece, piece))
	var side := XiangqiConstants.side_from_piece(piece)
	var from_coord := XiangqiCoord.from_index(from_index)
	var same_file_indices: Array = []
	for index: int in XiangqiConstants.BOARD_SIZE:
		if state_before_move.get_piece_at(index) != piece:
			continue
		var coord := XiangqiCoord.from_index(index)
		if coord.x == from_coord.x:
			same_file_indices.push_back(index)

	if same_file_indices.size() <= 1 or same_file_indices.size() > 3:
		return piece_label + _file_text(side, from_coord.x)

	var ordered_indices := _sort_indices_from_front(same_file_indices, side)
	var position_from_front := ordered_indices.find(from_index)
	if position_from_front == -1:
		return piece_label + _file_text(side, from_coord.x)

	if same_file_indices.size() == 2:
		return ("\u524d" if position_from_front == 0 else "\u540e") + piece_label
	return ["\u524d", "\u4e2d", "\u540e"][position_from_front] + piece_label

static func _action_text(piece: String, side: int, from_coord: Vector2i, to_coord: Vector2i) -> String:
	if from_coord.y == to_coord.y:
		return "\u5e73" + _file_text(side, to_coord.x)

	var piece_type := XiangqiConstants.piece_type(piece)
	var moving_forward := _is_forward_move(side, from_coord.y, to_coord.y)
	var action := "\u8fdb" if moving_forward else "\u9000"
	if piece_type in ["h", "e", "a"]:
		return action + _file_text(side, to_coord.x)
	return action + _step_text(side, abs(to_coord.y - from_coord.y))

static func _is_forward_move(side: int, from_rank: int, to_rank: int) -> bool:
	return to_rank < from_rank if side == XiangqiConstants.RED else to_rank > from_rank

static func _file_text(side: int, file: int) -> String:
	var file_number := 9 - file if side == XiangqiConstants.RED else file + 1
	return _number_text(side, file_number)

static func _step_text(side: int, step_count: int) -> String:
	return _number_text(side, step_count)

static func _number_text(_side: int, number: int) -> String:
	return RED_NUMERALS[number] if number >= 0 and number < RED_NUMERALS.size() else str(number)

static func _sort_indices_from_front(indices: Array, side: int) -> Array:
	var sorted: Array = []
	for index_variant in indices:
		var index := int(index_variant)
		var inserted := false
		var rank := XiangqiCoord.from_index(index).y
		for sorted_index: int in range(sorted.size()):
			var other_index := int(sorted[sorted_index])
			var other_rank := XiangqiCoord.from_index(other_index).y
			if _is_closer_to_front(side, rank, other_rank):
				sorted.insert(sorted_index, index)
				inserted = true
				break
		if !inserted:
			sorted.push_back(index)
	return sorted

static func _is_closer_to_front(side: int, rank_a: int, rank_b: int) -> bool:
	return rank_a < rank_b if side == XiangqiConstants.RED else rank_a > rank_b
