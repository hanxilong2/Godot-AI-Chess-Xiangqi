extends Node
class_name PikafishAdapter

signal engine_started()
signal engine_stopped()
signal line_received(line: String)
signal bestmove_received(move: XiangqiMove, move_text: String)
signal engine_error(message: String)

const MATE_SCORE_CP := 100000
const RUNTIME_ENGINE_DIR := "user://pikafish"
const COPY_BUFFER_SIZE := 1024 * 1024

@export_file("*.exe") var executable_path: String = "res://resource/xiangqi/bin/pikafish/pikafish.exe"
@export_file("*.nnue") var eval_file_path: String = "res://resource/xiangqi/bin/pikafish/pikafish.nnue"
@export var default_movetime_ms: int = 1000
@export_range(1, 4, 1) var engine_threads: int = 1
@export_range(16, 512, 16) var engine_hash_mb: int = 64
@export_range(0, 20, 1) var skill_level: int = 20
@export var startup_timeout_ms: int = 5000
@export var ready_timeout_ms: int = 5000
@export var search_timeout_padding_ms: int = 3000

var pid: int = -1
var stdio: FileAccess = null
var stderr: FileAccess = null
var started := false
var uci_ready := false
var last_bestmove_text := ""
var last_bestmove: XiangqiMove = null
var last_score_type := ""
var last_score_value := 0
var last_score_depth := 0
var last_score_pv := ""
var last_wdl_win := -1
var last_wdl_draw := -1
var last_wdl_loss := -1
var last_error := ""
var emit_runtime_signals := true
var push_runtime_errors := true
var output_log: PackedStringArray = PackedStringArray()

func _exit_tree() -> void:
	stop_engine()

func is_engine_running() -> bool:
	return started and pid > 0 and OS.is_process_running(pid)

func start_engine() -> bool:
	if is_engine_running():
		return true

	var global_executable_path := _resolve_external_runtime_file(executable_path)
	if !FileAccess.file_exists(global_executable_path):
		_report_error("Pikafish executable not found: %s" % executable_path)
		return false

	var process: Dictionary = OS.execute_with_pipe(global_executable_path, PackedStringArray(), false)
	pid = int(process.get("pid", -1))
	stdio = process.get("stdio") as FileAccess
	stderr = process.get("stderr") as FileAccess
	if pid <= 0 or stdio == null:
		_report_error("Failed to start Pikafish process.")
		stop_engine()
		return false

	started = true
	uci_ready = false
	_reset_search_result()
	output_log.clear()
	last_error = ""
	if emit_runtime_signals:
		engine_started.emit()
	return true

func initialize_engine() -> bool:
	if !start_engine():
		return false

	send_command("uci")
	if !_wait_for_token("uciok", startup_timeout_ms):
		_report_error("Pikafish did not answer uciok.")
		return false

	uci_ready = true
	_configure_engine_limits()
	_configure_eval_file()
	return wait_until_ready()

func wait_until_ready(timeout_ms: int = -1) -> bool:
	if !is_engine_running():
		_report_error("Pikafish is not running.")
		return false
	send_command("isready")
	var effective_timeout := ready_timeout_ms if timeout_ms < 0 else timeout_ms
	if !_wait_for_token("readyok", effective_timeout):
		_report_error("Pikafish did not answer readyok.")
		return false
	return true

func new_game() -> bool:
	if !uci_ready and !initialize_engine():
		return false
	send_command("ucinewgame")
	return wait_until_ready()

func request_bestmove_for_state(state: XiangqiState, movetime_ms: int = -1, moves: Array = []) -> XiangqiMove:
	if state == null:
		_report_error("Cannot search a null XiangqiState.")
		return null
	return request_bestmove(XiangqiFen.to_fen(state), movetime_ms, moves, state)

func request_analysis_for_state(state: XiangqiState, movetime_ms: int = -1, depth: int = 0, moves: Array = []) -> Dictionary:
	if state == null:
		_report_error("Cannot analyze a null XiangqiState.")
		return {}
	if depth > 0:
		return request_analysis_depth(state.to_fen(), depth, moves, state)
	return request_analysis(state.to_fen(), movetime_ms, moves, state)

func request_bestmove(fen: String, movetime_ms: int = -1, moves: Array = [], state: XiangqiState = null) -> XiangqiMove:
	var bestmove_text := request_bestmove_text(fen, movetime_ms, moves)
	if bestmove_text.is_empty() or bestmove_text == "0000" or bestmove_text == "(none)":
		return null
	var move: XiangqiMove = _move_from_engine_text(bestmove_text, state)
	if !move.is_valid():
		_report_error("Pikafish returned an invalid bestmove: %s" % bestmove_text)
		return null
	last_bestmove = move
	if emit_runtime_signals:
		bestmove_received.emit(move.duplicate(), bestmove_text)
	return move

func request_analysis(fen: String, movetime_ms: int = -1, moves: Array = [], state: XiangqiState = null) -> Dictionary:
	var bestmove_text := request_bestmove_text(fen, movetime_ms, moves)
	return _build_analysis_result(bestmove_text, state)

func request_bestmove_text(fen: String, movetime_ms: int = -1, moves: Array = []) -> String:
	if !uci_ready and !initialize_engine():
		return ""

	var effective_movetime := default_movetime_ms if movetime_ms < 0 else movetime_ms
	_reset_search_result()
	send_position(fen, moves)
	send_command("go movetime %d" % effective_movetime)
	var timeout := effective_movetime + search_timeout_padding_ms
	if !_wait_for_bestmove(timeout):
		_report_error("Pikafish did not return bestmove within %d ms." % timeout)
		return ""
	return last_bestmove_text

func request_bestmove_depth(fen: String, depth: int = 1, moves: Array = [], state: XiangqiState = null) -> XiangqiMove:
	var bestmove_text := request_bestmove_text_depth(fen, depth, moves)
	if bestmove_text.is_empty() or bestmove_text == "0000" or bestmove_text == "(none)":
		return null
	var move: XiangqiMove = _move_from_engine_text(bestmove_text, state)
	if !move.is_valid():
		_report_error("Pikafish returned an invalid bestmove: %s" % bestmove_text)
		return null
	last_bestmove = move
	if emit_runtime_signals:
		bestmove_received.emit(move.duplicate(), bestmove_text)
	return move

func request_analysis_depth(fen: String, depth: int = 1, moves: Array = [], state: XiangqiState = null) -> Dictionary:
	var bestmove_text := request_bestmove_text_depth(fen, depth, moves)
	return _build_analysis_result(bestmove_text, state)

func request_bestmove_text_depth(fen: String, depth: int = 1, moves: Array = []) -> String:
	if !uci_ready and !initialize_engine():
		return ""

	_reset_search_result()
	send_position(fen, moves)
	send_command("go depth %d" % maxi(1, depth))
	var timeout := search_timeout_padding_ms + maxi(1, depth) * 1000
	if !_wait_for_bestmove(timeout):
		_report_error("Pikafish did not return bestmove within %d ms." % timeout)
		return ""
	return last_bestmove_text

func send_position(fen: String, moves: Array = []) -> void:
	var command := "position fen %s" % to_engine_fen(fen)
	var move_texts := _moves_to_texts(moves)
	if !move_texts.is_empty():
		command += " moves " + " ".join(move_texts)
	send_command(command)

func send_command(command: String) -> bool:
	if stdio == null:
		_report_error("Cannot send command because Pikafish stdio is closed.")
		return false
	stdio.store_string(command + "\n")
	stdio.flush()
	return true

func stop_engine() -> void:
	if stdio != null:
		if is_engine_running():
			stdio.store_string("quit\n")
			stdio.flush()
		stdio.close()
	if stderr != null:
		stderr.close()
	stdio = null
	stderr = null
	pid = -1
	started = false
	uci_ready = false
	if emit_runtime_signals:
		engine_stopped.emit()

func parse_bestmove_line(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.size() >= 2 and parts[0] == "bestmove":
		return parts[1]
	return ""

func parse_info_score_line(line: String) -> Dictionary:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty() or parts[0] != "info":
		return {}

	var multipv_index := parts.find("multipv")
	if multipv_index >= 0 and multipv_index + 1 < parts.size():
		var multipv_text := parts[multipv_index + 1]
		if multipv_text.is_valid_int() and int(multipv_text) != 1:
			return {}

	var score_index := parts.find("score")
	if score_index < 0 or score_index + 2 >= parts.size():
		return {}

	var score_type := parts[score_index + 1]
	var score_text := parts[score_index + 2]
	if score_type != "cp" and score_type != "mate":
		return {}
	if !score_text.is_valid_int():
		return {}

	var depth := 0
	var depth_index := parts.find("depth")
	if depth_index >= 0 and depth_index + 1 < parts.size() and parts[depth_index + 1].is_valid_int():
		depth = int(parts[depth_index + 1])

	var pv := ""
	var pv_index := parts.find("pv")
	if pv_index >= 0 and pv_index + 1 < parts.size():
		pv = parts[pv_index + 1]

	var wdl_win := -1
	var wdl_draw := -1
	var wdl_loss := -1
	var wdl_index := parts.find("wdl")
	if wdl_index >= 0 and wdl_index + 3 < parts.size():
		var win_text := parts[wdl_index + 1]
		var draw_text := parts[wdl_index + 2]
		var loss_text := parts[wdl_index + 3]
		if win_text.is_valid_int() and draw_text.is_valid_int() and loss_text.is_valid_int():
			wdl_win = int(win_text)
			wdl_draw = int(draw_text)
			wdl_loss = int(loss_text)

	return {
		"type": score_type,
		"value": int(score_text),
		"depth": depth,
		"pv": pv,
		"wdl_win": wdl_win,
		"wdl_draw": wdl_draw,
		"wdl_loss": wdl_loss,
	}

func to_engine_fen(fen: String) -> String:
	var parts := fen.strip_edges().split(" ", false)
	if parts.is_empty():
		return fen.strip_edges()
	parts[0] = _to_engine_board_text(parts[0])
	return " ".join(parts)

func _configure_eval_file() -> void:
	var global_eval_file_path := _resolve_external_runtime_file(eval_file_path)
	if FileAccess.file_exists(global_eval_file_path):
		send_command("setoption name EvalFile value %s" % global_eval_file_path)

func _resolve_external_runtime_file(path: String) -> String:
	if path.begins_with("res://"):
		var runtime_path := "%s/%s" % [RUNTIME_ENGINE_DIR, path.get_file()]
		if _copy_resource_file_if_needed(path, runtime_path):
			return ProjectSettings.globalize_path(runtime_path)
	return ProjectSettings.globalize_path(path)

func _copy_resource_file_if_needed(source_path: String, target_path: String) -> bool:
	if !FileAccess.file_exists(source_path):
		return false

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var source_length := source.get_length()

	if FileAccess.file_exists(target_path):
		var existing := FileAccess.open(target_path, FileAccess.READ)
		if existing != null:
			var existing_length := existing.get_length()
			existing.close()
			if existing_length == source_length:
				source.close()
				return true

	var target_dir := target_path.get_base_dir()
	if DirAccess.open(target_dir) == null:
		DirAccess.make_dir_recursive_absolute(target_dir)

	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		source.close()
		return false

	while source.get_position() < source_length:
		var remaining := source_length - source.get_position()
		target.store_buffer(source.get_buffer(mini(COPY_BUFFER_SIZE, remaining)))

	source.close()
	target.close()
	return FileAccess.file_exists(target_path)

func _configure_engine_limits() -> void:
	send_command("setoption name Threads value %d" % maxi(1, engine_threads))
	send_command("setoption name Hash value %d" % maxi(16, engine_hash_mb))
	if _supports_uci_option("Skill Level"):
		send_command("setoption name Skill Level value %d" % clampi(skill_level, 0, 20))
	if _supports_uci_option("UCI_ShowWDL"):
		send_command("setoption name UCI_ShowWDL value true")

func _supports_uci_option(option_name: String) -> bool:
	var prefix := "option name %s " % option_name
	for line in output_log:
		if line.to_lower().begins_with(prefix.to_lower()):
			return true
	return false

func _wait_for_token(token: String, timeout_ms: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at <= timeout_ms:
		var line := _read_line()
		if line == token:
			return true
		if !is_engine_running():
			return false
		await_or_spin_frame()
	return false

func _wait_for_bestmove(timeout_ms: int) -> bool:
	var started_at := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started_at <= timeout_ms:
		var line := _read_line()
		_update_last_score_from_info_line(line)
		var bestmove_text := parse_bestmove_line(line)
		if !bestmove_text.is_empty():
			last_bestmove_text = bestmove_text
			return true
		if !is_engine_running():
			return false
		await_or_spin_frame()
	return false

func _read_line() -> String:
	if stdio == null:
		return ""
	var line := stdio.get_line().strip_edges()
	if line.is_empty():
		return ""
	output_log.append(line)
	if emit_runtime_signals:
		line_received.emit(line)
	return line

func await_or_spin_frame() -> void:
	OS.delay_msec(1)

func _reset_search_result() -> void:
	last_bestmove_text = ""
	last_bestmove = null
	last_score_type = ""
	last_score_value = 0
	last_score_depth = 0
	last_score_pv = ""
	last_wdl_win = -1
	last_wdl_draw = -1
	last_wdl_loss = -1

func _update_last_score_from_info_line(line: String) -> void:
	var score := parse_info_score_line(line)
	if score.is_empty():
		return
	last_score_type = String(score.get("type", ""))
	last_score_value = int(score.get("value", 0))
	last_score_depth = int(score.get("depth", 0))
	last_score_pv = String(score.get("pv", ""))
	last_wdl_win = int(score.get("wdl_win", -1))
	last_wdl_draw = int(score.get("wdl_draw", -1))
	last_wdl_loss = int(score.get("wdl_loss", -1))

func _score_to_centipawns(score_type: String, score_value: int) -> int:
	if score_type == "cp":
		return score_value
	if score_type == "mate":
		if score_value == 0:
			return 0
		return MATE_SCORE_CP if score_value > 0 else -MATE_SCORE_CP
	return 0

func _has_wdl_triplet(wdl_win: int, wdl_draw: int, wdl_loss: int) -> bool:
	return wdl_win >= 0 and wdl_draw >= 0 and wdl_loss >= 0

func _wdl_to_expected_score(wdl_win: int, wdl_draw: int, wdl_loss: int) -> int:
	if !_has_wdl_triplet(wdl_win, wdl_draw, wdl_loss):
		return -1
	return int(roundf(float(wdl_win) + float(wdl_draw) * 0.5))

func _build_analysis_result(bestmove_text: String, state: XiangqiState = null) -> Dictionary:
	var move: XiangqiMove = null
	if !bestmove_text.is_empty() and bestmove_text != "0000" and bestmove_text != "(none)":
		move = _move_from_engine_text(bestmove_text, state)
		if move.is_valid():
			last_bestmove = move
			if emit_runtime_signals:
				bestmove_received.emit(move.duplicate(), bestmove_text)
		else:
			move = null
	return {
		"ok": !bestmove_text.is_empty(),
		"bestmove_text": bestmove_text,
		"bestmove": move,
		"score_type": last_score_type,
		"score_value": last_score_value,
		"score_cp": _score_to_centipawns(last_score_type, last_score_value),
		"score_depth": last_score_depth,
		"score_pv": last_score_pv,
		"wdl_win": last_wdl_win,
		"wdl_draw": last_wdl_draw,
		"wdl_loss": last_wdl_loss,
		"expected_score_permille": _wdl_to_expected_score(last_wdl_win, last_wdl_draw, last_wdl_loss),
	}

func _moves_to_texts(moves: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for move_variant in moves:
		if move_variant is XiangqiMove:
			var move := move_variant as XiangqiMove
			var text := _move_to_engine_text(move)
			if !text.is_empty():
				result.append(text)
		else:
			var text := String(move_variant).strip_edges()
			if !text.is_empty():
				result.append(text)
	return result

func _move_from_engine_text(text: String, state: XiangqiState = null) -> XiangqiMove:
	if text.length() < 4:
		return XiangqiMove.new()
	var move := XiangqiMove.new(
		_engine_square_to_index(text.substr(0, 2)),
		_engine_square_to_index(text.substr(2, 2))
	)
	if state != null and move.from_index != -1:
		move.piece = state.get_piece_at(move.from_index)
		move.captured_piece = state.get_piece_at(move.to_index)
		if !move.captured_piece.is_empty():
			move.flags |= XiangqiConstants.FLAG_CAPTURE
	return move

func _move_to_engine_text(move: XiangqiMove) -> String:
	if move == null or !move.is_valid():
		return ""
	return _index_to_engine_square(move.from_index) + _index_to_engine_square(move.to_index)

func _engine_square_to_index(square: String) -> int:
	if square.length() < 2:
		return -1
	var file_name := square.substr(0, 1).to_lower()
	if !XiangqiConstants.FILE_NAMES.has(file_name):
		return -1
	var rank_text := square.substr(1)
	if !rank_text.is_valid_int():
		return -1
	var file := XiangqiConstants.FILE_NAMES.find(file_name)
	var engine_rank := int(rank_text)
	var internal_rank := XiangqiConstants.BOARD_RANKS - 1 - engine_rank
	return XiangqiCoord.to_index(file, internal_rank)

func _index_to_engine_square(index: int) -> String:
	if !XiangqiCoord.is_valid_index(index):
		return ""
	var coord := XiangqiCoord.from_index(index)
	var engine_rank := XiangqiConstants.BOARD_RANKS - 1 - coord.y
	return "%s%d" % [XiangqiConstants.FILE_NAMES[coord.x], engine_rank]

func _to_engine_board_text(board_text: String) -> String:
	var result := ""
	for index: int in board_text.length():
		var token := board_text.substr(index, 1)
		match token:
			"H":
				result += "N"
			"h":
				result += "n"
			"E":
				result += "B"
			"e":
				result += "b"
			_:
				result += token
	return result

func _report_error(message: String) -> void:
	last_error = message
	if push_runtime_errors:
		push_error(message)
	if emit_runtime_signals:
		engine_error.emit(message)
