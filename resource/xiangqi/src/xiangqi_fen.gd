extends RefCounted
class_name XiangqiFen

static func create_state(fen: String = XiangqiConstants.START_FEN) -> XiangqiState:
	var state := XiangqiState.new()
	apply_to_state(state, fen)
	return state

static func apply_to_state(state, fen: String) -> bool:
	if state == null:
		return false
	var cleaned_fen := fen.strip_edges()
	if cleaned_fen.is_empty():
		return false
	var parts := cleaned_fen.split(" ", false)
	if parts.is_empty():
		return false
	var rows := parts[0].split("/")
	if rows.size() != XiangqiConstants.BOARD_RANKS:
		return false

	var new_board: Array = []
	for index: int in XiangqiConstants.BOARD_SIZE:
		new_board.push_back("")

	for rank: int in XiangqiConstants.BOARD_RANKS:
		var row: String = rows[rank]
		var file := 0
		for char_index: int in row.length():
			var token := row.substr(char_index, 1)
			if token.is_valid_int():
				var empty_count := int(token)
				if empty_count <= 0:
					return false
				file += empty_count
				if file > XiangqiConstants.BOARD_FILES:
					return false
				continue
			var piece := XiangqiConstants.normalize_fen_piece(token)
			if piece.is_empty():
				return false
			if file >= XiangqiConstants.BOARD_FILES:
				return false
			new_board[XiangqiCoord.to_index(file, rank)] = piece
			file += 1
		if file != XiangqiConstants.BOARD_FILES:
			return false

	var side := XiangqiConstants.RED
	if parts.size() > 1:
		if !XiangqiConstants.is_valid_side_token(parts[1]):
			return false
		side = XiangqiConstants.token_to_side(parts[1])

	state.load_board(
		new_board,
		side,
		maxi(0, int(parts[4])) if parts.size() > 4 and parts[4].is_valid_int() else 0,
		maxi(1, int(parts[5])) if parts.size() > 5 and parts[5].is_valid_int() else 1
	)
	return true

static func to_fen(state: XiangqiState) -> String:
	var rows := PackedStringArray()
	for rank: int in XiangqiConstants.BOARD_RANKS:
		var row := ""
		var empty := 0
		for file: int in XiangqiConstants.BOARD_FILES:
			var piece := state.get_piece_at(XiangqiCoord.to_index(file, rank))
			if piece.is_empty():
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			row += piece
		if empty > 0:
			row += str(empty)
		rows.append(row)

	var board_text := ""
	for row_index: int in rows.size():
		if row_index > 0:
			board_text += "/"
		board_text += rows[row_index]

	return "%s %s - - %d %d" % [
		board_text,
		XiangqiConstants.side_to_token(state.side_to_move),
		state.halfmove_clock,
		state.fullmove_number,
	]
