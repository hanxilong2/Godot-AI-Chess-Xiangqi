extends Node
class_name ChessAIWrapper

## AI wrapper
## 用于在GDScript中调用C#的AI模块

signal ai_response(response_type: String, content: String)
signal review_generated(review_content: String, review_data: String)

const DEBUG_AI_WRAPPER: bool = false

var _ai_module: Node = null
var _is_available: bool = false
var _connected_signals: Array = []

func _ready() -> void:
	_check_ai_availability()

func _exit_tree() -> void:
	_disconnect_ai_signals()

func _check_ai_availability() -> void:
	_ai_module = get_node_or_null("/root/ChessAI")
	_is_available = _ai_module != null

	if _is_available:
		_connect_ai_signals()
		if _ai_module.has_method("IsModuleReady"):
			_is_available = bool(_ai_module.call("IsModuleReady"))
		elif _ai_module.has_method("is_module_ready"):
			_is_available = bool(_ai_module.call("is_module_ready"))
		if DEBUG_AI_WRAPPER:
			prints("[ChessAIWrapper] AI模块已连接")
			if _ai_module.has_method("TestAI"):
				_ai_module.call("TestAI")
			elif _ai_module.has_method("test_ai"):
				_ai_module.call("test_ai")
	else:
		if DEBUG_AI_WRAPPER:
			prints("[ChessAIWrapper] AI模块未找到，请检查Autoload配置")

func _connect_ai_signals() -> void:
	_connect_first_signal(
		["ai_response_received", "AiResponseReceived"],
		Callable(self, "_on_ai_response_received")
	)
	_connect_first_signal(
		["review_generated_received", "ReviewGeneratedReceived"],
		Callable(self, "_on_review_generated_received")
	)

func _connect_first_signal(signal_names: Array, callback: Callable) -> void:
	if _ai_module == null:
		return
	for signal_name in signal_names:
		if _ai_module.has_signal(signal_name):
			if !_ai_module.is_connected(signal_name, callback):
				_ai_module.connect(signal_name, callback)
			_connected_signals.push_back({
				"signal_name": signal_name,
				"callback": callback,
			})
			return

func _disconnect_ai_signals() -> void:
	if _ai_module == null:
		_connected_signals.clear()
		return
	for connection in _connected_signals:
		if !(connection is Dictionary):
			continue
		var signal_name := String(connection.get("signal_name", ""))
		var callback := connection.get("callback") as Callable
		if signal_name.is_empty() or callback.is_null():
			continue
		if _ai_module.has_signal(signal_name) and _ai_module.is_connected(signal_name, callback):
			_ai_module.disconnect(signal_name, callback)
	_connected_signals.clear()

## 检查AI模块是否可用
func is_available() -> bool:
	if !_is_available:
		_check_ai_availability()
	return _is_available

## 发送玩家消息
func send_player_message(message: String, session: Dictionary) -> void:
	if !_is_available:
		if DEBUG_AI_WRAPPER:
			prints("[ChessAIWrapper] AI模块不可用")
		return

	if DEBUG_AI_WRAPPER:
		prints("[ChessAIWrapper] 发送玩家消息:", message)
	_call_ai_method(
		["OnPlayerMessageJson", "on_player_message_json"],
		[message, JSON.stringify(session)]
	)

func set_api_key(api_key: String) -> bool:
	if !is_available():
		return false
	return _call_ai_method_bool(["SetApiKey", "set_api_key"], [api_key], false)

func clear_api_key() -> bool:
	if !is_available():
		return false
	return _call_ai_method_bool(["ClearApiKey", "clear_api_key"], [], false)

func clear_memory() -> bool:
	if !is_available():
		return false
	return _call_ai_method_bool(["ClearMemory", "clear_memory"], [], false)

func clear_chess_memory() -> bool:
	if !is_available():
		return false
	return _call_ai_method_bool(["ClearChessMemory", "clear_chess_memory"], [], false)

func clear_xiangqi_memory() -> bool:
	if !is_available():
		return false
	return _call_ai_method_bool(["ClearXiangqiMemory", "clear_xiangqi_memory"], [], false)

func archive_current_game_memory(session: Dictionary, result: String) -> bool:
	if !is_available():
		return false
	if DEBUG_AI_WRAPPER:
		prints("[ChessAIWrapper] 后台归档当前棋局记忆:", result)
	return _call_ai_method(
		["ArchiveCurrentGameMemoryJson", "archive_current_game_memory_json"],
		[JSON.stringify(session), result]
	)

func has_api_key() -> bool:
	if !is_available() or _ai_module == null:
		return false
	if _ai_module.has_method("HasApiKey"):
		return bool(_ai_module.call("HasApiKey"))
	if _ai_module.has_method("has_api_key"):
		return bool(_ai_module.call("has_api_key"))
	return false

func has_saved_api_key() -> bool:
	if !is_available() or _ai_module == null:
		return false
	if _ai_module.has_method("HasSavedApiKey"):
		return bool(_ai_module.call("HasSavedApiKey"))
	if _ai_module.has_method("has_saved_api_key"):
		return bool(_ai_module.call("has_saved_api_key"))
	return false

func set_banter_player_side(player_side: int) -> bool:
	if !is_available():
		return false
	return _call_ai_method(["SetBanterPlayerSide", "set_banter_player_side"], [player_side])

func set_chat_player_side(player_side: int) -> bool:
	if !is_available():
		return false
	return _call_ai_method(["SetChatPlayerSide", "set_chat_player_side"], [player_side])

func set_review_player_side(player_side: int) -> bool:
	if !is_available():
		return false
	return _call_ai_method(["SetReviewPlayerSide", "set_review_player_side"], [player_side])

## 发送走棋记录
func send_move_played(move_record: Dictionary, session: Dictionary) -> bool:
	if !_is_available:
		if DEBUG_AI_WRAPPER:
			prints("[ChessAIWrapper] AI模块不可用")
		return false

	if DEBUG_AI_WRAPPER:
		prints("========================================")
		prints("[ChessAIWrapper] 发送走棋记录给AI")
		prints("走法:", move_record.get("ChineseNotation", ""))
		prints("坐标:", move_record.get("CoordinateNotation", ""))
		prints("棋子:", move_record.get("Piece", ""))
		prints("评估分数:", move_record.get("EvaluationScore", 0))
		prints("最佳走法:", move_record.get("BestMove", ""))
		prints("皮卡鱼分析:", move_record.get("PikafishAnalysis", {}))
		prints("当前FEN:", session.get("CurrentFEN", ""))
		prints("走法数量:", session.get("MoveHistory", []).size())
		prints("========================================")
	return _call_ai_method(
		["OnMovePlayedJson", "on_move_played_json"],
		[JSON.stringify(move_record), JSON.stringify(session)]
	)

## 发送悔棋事件
func send_undo_performed(session: Dictionary, undone_count: int, undone_move_text: String = "") -> bool:
	if !_is_available:
		if DEBUG_AI_WRAPPER:
			prints("[ChessAIWrapper] AI模块不可用")
		return false

	if DEBUG_AI_WRAPPER:
		prints("[ChessAIWrapper] 发送悔棋事件给AI:", undone_count, undone_move_text)
	return _call_ai_method(
		["OnUndoPerformedJson", "on_undo_performed_json"],
		[JSON.stringify(session), undone_count, undone_move_text]
	)

## 发送游戏结束事件
func send_game_ended(session: Dictionary, result: String) -> void:
	if !_is_available:
		if DEBUG_AI_WRAPPER:
			prints("[ChessAIWrapper] AI模块不可用")
		return

	if DEBUG_AI_WRAPPER:
		prints("========================================")
		prints("[ChessAIWrapper] 发送游戏结束事件给AI")
		prints("游戏结果:", result)
		prints("游戏时长:", _calculate_game_duration(session))
		prints("总走法数:", session.get("MoveHistory", []).size())
		prints("当前FEN:", session.get("CurrentFEN", ""))
		prints("========================================")
	_call_ai_method(
		["OnGameEndedJson", "on_game_ended_json"],
		[JSON.stringify(session), result]
	)

func _call_ai_method(method_names: Array, args: Array) -> bool:
	if _ai_module == null:
		_is_available = false
		return false
	for method_name in method_names:
		if _ai_module.has_method(method_name):
			_ai_module.callv(method_name, args)
			return true
	push_error("[ChessAIWrapper] AI模块缺少可调用方法: %s" % ", ".join(method_names))
	return false

func _call_ai_method_bool(method_names: Array, args: Array, default_value: bool = false) -> bool:
	if _ai_module == null:
		_is_available = false
		return false
	for method_name in method_names:
		if _ai_module.has_method(method_name):
			var result = _ai_module.callv(method_name, args)
			return default_value if result == null else bool(result)
	push_error("[ChessAIWrapper] AI模块缺少可调用方法: %s" % ", ".join(method_names))
	return false

func _on_ai_response_received(response_type: String, content: String) -> void:
	if DEBUG_AI_WRAPPER:
		prints("[ChessAIWrapper] 收到AI响应:", response_type, content)
	ai_response.emit(response_type, content)

func _on_review_generated_received(review_content: String, review_data: String) -> void:
	if DEBUG_AI_WRAPPER:
		prints("[ChessAIWrapper] 收到AI复盘:", review_content)
	review_generated.emit(review_content, review_data)

## 计算游戏时长
func _calculate_game_duration(session: Dictionary) -> String:
	var move_count = session.get("MoveHistory", []).size()
	var estimated_minutes = move_count * 2  # 假设每步2分钟
	return str(estimated_minutes) + "分钟"

## 创建游戏会话数据
func create_game_session(board_state, human_side: int, ai_enabled: bool, initial_state = null) -> Dictionary:
	var initial_fen := XiangqiConstants.START_FEN
	if initial_state != null:
		initial_fen = initial_state.to_fen()
	var session = {
		"CurrentFEN": board_state.to_fen(),
		"InitialFEN": initial_fen,
		"GameVariant": tr("XIANGQI_GAME_VARIANT"),
		"Board": board_state.board.duplicate(),
		"CurrentPlayer": board_state.side_to_move,
		"HumanSide": human_side,
		"HalfmoveClock": board_state.halfmove_clock,
		"FullmoveNumber": board_state.fullmove_number,
		"MoveHistory": _convert_move_history(board_state, initial_state),
		"GameStatus": tr("GAME_STATUS_ACTIVE"),
		"GameResult": "",
		"AIEnabled": ai_enabled,
		"SessionId": str(Time.get_unix_time_from_system())
	}
	return session

## 转换走法历史
func _convert_move_history(board_state, initial_state = null) -> Array:
	var history = []
	var replay_state: XiangqiState = initial_state.duplicate() if initial_state != null else XiangqiFen.create_state(XiangqiConstants.START_FEN)
	for ply_index: int in range(board_state.move_history.size()):
		var move := board_state.move_history[ply_index] as XiangqiMove
		if move == null:
			continue
		var side: int = replay_state.side_to_move
		var move_record = {
			"FromIndex": move.from_index,
			"ToIndex": move.to_index,
			"Piece": move.piece,
			"CapturedPiece": move.captured_piece,
			"Flags": move.flags,
			"ChineseNotation": XiangqiNotation.move_to_chinese(replay_state, move),
			"CoordinateNotation": move.to_coordinate_string(),
			"Side": side,
			"PlyIndex": ply_index + 1,
			"MoveNumber": int(ply_index / 2) + 1,
			"EvaluationScore": 0,
			"BestMove": "",
			"PikafishAnalysis": {}
		}
		history.append(move_record)
		replay_state.apply_move(move)
	return history

## 创建走法记录
func create_move_record(move: XiangqiMove, evaluation_score: int = 0, best_move: String = "", move_number: int = 1) -> Dictionary:
	var side := XiangqiConstants.side_from_piece(move.piece)
	var move_record = {
		"FromIndex": move.from_index,
		"ToIndex": move.to_index,
		"Piece": move.piece,
		"CapturedPiece": move.captured_piece,
		"Flags": move.flags,
		"ChineseNotation": move.to_coordinate_string(),
		"CoordinateNotation": move.to_coordinate_string(),
		"Side": side,
		"PlyIndex": 0,
		"MoveNumber": move_number,
		"EvaluationScore": evaluation_score,
		"BestMove": best_move,
		"PikafishAnalysis": {}
	}
	return move_record
