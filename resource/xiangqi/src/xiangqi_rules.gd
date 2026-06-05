extends RefCounted
class_name XiangqiRules

const NATIVE_RULES_CPP_CLASS := &"XiangqiRulesNativeCpp"

static var _native_rules: RefCounted = null
static var _native_rules_error_reported: bool = false

static func implementation_stage() -> int:
	var native := _get_native_rules()
	if native == null or !native.has_method("implementation_stage"):
		return -1
	return int(native.call("implementation_stage"))

static func rules_ready() -> bool:
	var native := _get_native_rules()
	return native != null and native.has_method("rules_ready") and bool(native.call("rules_ready"))

static func generate_pseudo_legal_moves(state: XiangqiState, from_index: int = -1) -> Array:
	if state == null:
		return []
	var native := _get_native_rules()
	if native == null or !native.has_method("generate_pseudo_legal_moves"):
		return []
	return _decode_native_moves(native.call("generate_pseudo_legal_moves", _rules_state(state), from_index))

static func generate_pseudo_legal_moves_for_side(state: XiangqiState, side: int, from_index: int = -1) -> Array:
	if state == null:
		return []
	var native := _get_native_rules()
	if native == null or !native.has_method("generate_pseudo_legal_moves_for_side"):
		return []
	return _decode_native_moves(native.call("generate_pseudo_legal_moves_for_side", _rules_state(state), side, from_index))

static func generate_legal_moves(state: XiangqiState, side: int = -1, from_index: int = -1) -> Array:
	if state == null:
		return []
	var native := _get_native_rules()
	if native == null or !native.has_method("generate_legal_moves"):
		return []
	return _decode_native_moves(native.call("generate_legal_moves", _rules_state(state), _resolve_side(state, side), from_index))

static func is_legal_move(state: XiangqiState, move: XiangqiMove, side: int = -1) -> bool:
	if state == null or move == null or !move.is_valid():
		return false
	var native := _get_native_rules()
	if native == null or !native.has_method("is_legal_move"):
		return false
	return bool(native.call("is_legal_move", _rules_state(state), move, _resolve_side(state, side)))

static func is_in_check(state: XiangqiState, side: int) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native == null or !native.has_method("is_in_check"):
		return false
	return bool(native.call("is_in_check", _rules_state(state), side))

static func are_generals_facing(state: XiangqiState) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native == null or !native.has_method("are_generals_facing"):
		return false
	return bool(native.call("are_generals_facing", _rules_state(state)))

static func has_any_legal_move(state: XiangqiState, side: int = -1, from_index: int = -1) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native == null or !native.has_method("has_any_legal_move"):
		return false
	return bool(native.call("has_any_legal_move", _rules_state(state), _resolve_side(state, side), from_index))

static func is_checkmate(state: XiangqiState, side: int = -1) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native == null or !native.has_method("is_checkmate"):
		return false
	return bool(native.call("is_checkmate", _rules_state(state), _resolve_side(state, side)))

static func is_stalemate(state: XiangqiState, side: int = -1) -> bool:
	if state == null:
		return false
	var native := _get_native_rules()
	if native == null or !native.has_method("is_stalemate"):
		return false
	return bool(native.call("is_stalemate", _rules_state(state), _resolve_side(state, side)))

static func get_position_status(state: XiangqiState, side: int = -1) -> String:
	if state == null:
		return "invalid"
	var native := _get_native_rules()
	if native == null or !native.has_method("get_position_status"):
		return "invalid"
	return String(native.call("get_position_status", _rules_state(state), _resolve_side(state, side)))

static func get_status_text() -> String:
	return "C++ Xiangqi rules ready." if rules_ready() else "C++ Xiangqi rules unavailable."

static func _get_native_rules() -> RefCounted:
	if _native_rules != null:
		return _native_rules

	if !ClassDB.class_exists(NATIVE_RULES_CPP_CLASS):
		_report_native_rules_error("Required native class XiangqiRulesNativeCpp is not registered. Rebuild or load siamese.gdextension.")
		return null

	_native_rules = ClassDB.instantiate(NATIVE_RULES_CPP_CLASS) as RefCounted
	if _native_rules == null:
		_report_native_rules_error("Failed to instantiate XiangqiRulesNativeCpp from siamese.gdextension.")
	return _native_rules

static func _rules_state(state: XiangqiState) -> Variant:
	if state == null:
		return null
	if state.native_state == null:
		state.call("_ensure_native_state")
	return state.native_state

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

static func _report_native_rules_error(message: String) -> void:
	if _native_rules_error_reported:
		return
	push_error(message)
	_native_rules_error_reported = true
