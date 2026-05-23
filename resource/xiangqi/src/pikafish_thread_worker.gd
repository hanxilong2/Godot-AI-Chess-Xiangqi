extends RefCounted
class_name PikafishThreadWorker

const PikafishAdapterScript := preload("res://resource/xiangqi/src/pikafish_adapter.gd")

func run_bestmove(state: XiangqiState, movetime_ms: int, depth: int, skill_level: int = 20) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"move": null,
		"error": "",
	}
	if state == null:
		result["error"] = "Cannot search a null XiangqiState."
		return result

	var adapter: PikafishAdapter = PikafishAdapterScript.new()
	adapter.emit_runtime_signals = false
	adapter.push_runtime_errors = false
	adapter.skill_level = clampi(skill_level, 0, 20)
	var search_state: XiangqiState = state.duplicate()
	var move: XiangqiMove = null
	if depth > 0:
		move = adapter.request_bestmove_depth(search_state.to_fen(), depth, [], search_state)
	else:
		move = adapter.request_bestmove_for_state(search_state, movetime_ms)

	if move != null and move.is_valid():
		result["ok"] = true
		result["move"] = move.duplicate()
	else:
		result["error"] = _adapter_error(adapter, "Pikafish did not return a usable move.")

	_release_adapter(adapter)
	return result

func run_player_move_analysis(
	before_state: XiangqiState,
	after_state: XiangqiState,
	played_move: XiangqiMove,
	movetime_ms: int,
	depth: int
) -> Dictionary:
	var result: Dictionary = {
		"ok": false,
		"evaluation_score": 0,
		"best_move": "",
		"played_move": "",
		"is_engine_best_move": false,
		"before": {},
		"after": {},
		"error": "",
	}
	if before_state == null or after_state == null or played_move == null or !played_move.is_valid():
		result["error"] = "Cannot analyze an incomplete player move."
		return result

	var adapter: PikafishAdapter = PikafishAdapterScript.new()
	adapter.emit_runtime_signals = false
	adapter.push_runtime_errors = false
	var safe_before_state: XiangqiState = before_state.duplicate()
	var safe_after_state: XiangqiState = after_state.duplicate()
	var safe_played_move: XiangqiMove = played_move.duplicate()
	var before_analysis: Dictionary = adapter.request_analysis_for_state(
		safe_before_state,
		movetime_ms,
		depth
	)
	var after_analysis: Dictionary = adapter.request_analysis_for_state(
		safe_after_state,
		movetime_ms,
		depth
	)

	if before_analysis.is_empty() or after_analysis.is_empty():
		result["error"] = _adapter_error(adapter, "Pikafish did not return a usable analysis.")
		_release_adapter(adapter)
		return result

	var best_move_text: String = _analysis_best_move_text(before_analysis)
	var before_score: int = int(before_analysis.get("score_cp", 0))
	var after_score: int = int(after_analysis.get("score_cp", 0))
	var player_after_score: int = -after_score
	var evaluation_loss: int = maxi(0, before_score - player_after_score)
	var is_engine_best_move := !best_move_text.is_empty() and best_move_text == safe_played_move.to_coordinate_string()
	if is_engine_best_move:
		evaluation_loss = 0

	result["ok"] = true
	result["evaluation_score"] = evaluation_loss
	result["played_move"] = safe_played_move.to_coordinate_string()
	result["is_engine_best_move"] = is_engine_best_move
	result["best_move"] = _format_best_move(before_analysis, safe_before_state)
	result["before"] = _analysis_summary(before_analysis, safe_before_state)
	result["after"] = _analysis_summary(after_analysis, safe_after_state)
	_release_adapter(adapter)
	return result

func _analysis_best_move_text(analysis: Dictionary) -> String:
	var best_move := analysis.get("bestmove") as XiangqiMove
	if best_move != null and best_move.is_valid():
		return best_move.to_coordinate_string()
	return String(analysis.get("bestmove_text", ""))

func _format_best_move(analysis: Dictionary, state: XiangqiState) -> String:
	var best_move := analysis.get("bestmove") as XiangqiMove
	if best_move == null or !best_move.is_valid():
		return String(analysis.get("bestmove_text", ""))
	var coordinate := best_move.to_coordinate_string()
	var notation := XiangqiNotation.move_to_chinese(state, best_move)
	if notation.is_empty():
		return coordinate
	return "%s (%s)" % [notation, coordinate]

func _analysis_summary(analysis: Dictionary, state: XiangqiState) -> Dictionary:
	return {
		"score_type": String(analysis.get("score_type", "")),
		"score_value": int(analysis.get("score_value", 0)),
		"score_cp": int(analysis.get("score_cp", 0)),
		"score_depth": int(analysis.get("score_depth", 0)),
		"score_pv": String(analysis.get("score_pv", "")),
		"wdl_win": int(analysis.get("wdl_win", -1)),
		"wdl_draw": int(analysis.get("wdl_draw", -1)),
		"wdl_loss": int(analysis.get("wdl_loss", -1)),
		"expected_score_permille": int(analysis.get("expected_score_permille", -1)),
		"best_move": _format_best_move(analysis, state),
	}

func _adapter_error(adapter: PikafishAdapter, fallback: String) -> String:
	if adapter != null and !adapter.last_error.is_empty():
		return adapter.last_error
	return fallback

func _release_adapter(adapter: PikafishAdapter) -> void:
	if adapter == null:
		return
	adapter.stop_engine()
	adapter.free()
