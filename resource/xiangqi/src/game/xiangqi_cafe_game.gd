extends Level

signal api_key_screen_closed()
signal xiangqi_game_finished()

const PLAYER_SCENE := preload("res://scene/common/player.tscn")
const CHESHIRE_SCENE := preload("res://scene/actor/cheshire.tscn")
const PikafishAdapterScript := preload("res://resource/xiangqi/src/pikafish_adapter.gd")
const PikafishThreadWorkerScript := preload("res://resource/xiangqi/src/pikafish_thread_worker.gd")
const CAMERA_TRANSITION_SECONDS := 0.5
const OPTION_PLAY_AS_RED := "XIANGQI_SELECTION_PLAY_AS_RED"
const OPTION_PLAY_AS_BLACK := "XIANGQI_SELECTION_PLAY_AS_BLACK"
const OPTION_PLAY_AS_RANDOM := "SELECTION_PLAY_AS_RANDOM"
const OPTION_XIANGQI_DIFFICULTY_STANDARD := "SELECTION_DIFFICULTY_STANDARD"
const OPTION_XIANGQI_DIFFICULTY_RELAX := "SELECTION_DIFFICULTY_RELAX"
const OPTION_CANCEL := "SELECTION_CANCEL"
const RADIO_MUSIC_DIRECTORY := "res://assets/audio"
const RADIO_MUSIC_IMPORT_SUFFIX := ".mp3.import"
const RADIO_MUSIC_EXCLUDED_FILES := [
	"719560__dartekz_gamez__wind-whirl-small-air-blow.mp3",
	"chess_clock_tick.mp3",
]
const RADIO_MUSIC_OPTION_PREVIOUS := "RADIO_MUSIC_OPTION_PREVIOUS"
const RADIO_MUSIC_OPTION_NEXT := "RADIO_MUSIC_OPTION_NEXT"
const RADIO_MUSIC_OPTION_VOLUME_HIGH := "RADIO_MUSIC_OPTION_VOLUME_HIGH"
const RADIO_MUSIC_OPTION_VOLUME_MEDIUM := "RADIO_MUSIC_OPTION_VOLUME_MEDIUM"
const RADIO_MUSIC_OPTION_VOLUME_LOW := "RADIO_MUSIC_OPTION_VOLUME_LOW"
const RADIO_MUSIC_OPTION_PLAY := "RADIO_MUSIC_OPTION_PLAY"
const RADIO_MUSIC_OPTION_STOP := "RADIO_MUSIC_OPTION_STOP"
const RADIO_MUSIC_OPTION_EXIT := "RADIO_MUSIC_OPTION_EXIT"
const RADIO_MUSIC_VOLUME_HIGH := "high"
const RADIO_MUSIC_VOLUME_MEDIUM := "medium"
const RADIO_MUSIC_VOLUME_LOW := "low"
const AI_AGENT_TOOL_NAMES := [
	"chat_with_player",
	"review_game",
	"banter_with_player",
]

enum MatchPhase {
	IDLE,
	PLAYER_TURN,
	AI_THINKING,
	GAME_OVER,
}

@export var start_fen: String = XiangqiConstants.START_FEN
@export var ai_enabled: bool = true
@export var ai_movetime_ms: int = 1000
@export var ai_search_depth: int = 0
@export var ai_skill_level: int = 20
@export var relax_ai_movetime_ms: int = 250
@export var relax_ai_search_depth: int = 2
@export_range(0, 20, 1) var relax_ai_skill_level: int = 3
@export var ai_agent_analysis_depth: int = 2
@export var ai_agent_analysis_movetime_ms: int = 120
@export var wait_for_ai_agent_before_pikafish: bool = true
@export var ai_agent_wait_timeout_sec: float = 120.0
@export var ai_agent_analysis_delay_sec: float = 0.5
@export var player_move_notation_refresh_delay_sec: float = 0.36

@onready var board: XiangqiBoard = $table_0/xiangqi_board_standard
@onready var player = $player
@onready var main_camera: Camera3D = $camera
@onready var board_camera: Camera3D = $camera_chessboard
@onready var paper_camera: Camera3D = $camera_paper
@onready var ai_io_camera: Camera3D = $camera_ai_io_paper
@onready var notation_paper: XiangqiNotationPaper3D = $table_0/xiangqi_notation_paper
@onready var ai_io_paper: Node = $table_0/xiangqi_ai_io_paper
@onready var top_bar: ColorRect = $ui_overlay/top_bar
@onready var top_label: Label = $ui_overlay/top_bar/top_label
@onready var bottom_bar: ColorRect = $ui_overlay/bottom_bar
@onready var undo_button: Button = $ui_overlay/bottom_bar/undo_button
@onready var leave_button: Button = $ui_overlay/bottom_bar/leave_button
@onready var review_button: Button = $ui_overlay/bottom_bar/review_button

var human_side: int = XiangqiConstants.RED
var xiangqi_ai_relax := false
var phase: int = MatchPhase.IDLE
var ai_adapter: Node = null
var chess_ai_wrapper: ChessAIWrapper = null
var api_key_button: Button = null
var api_key_screen: Control = null
var api_key_input: LineEdit = null
var api_key_status_label: Label = null
var api_key_save_button: Button = null
var api_key_clear_button: Button = null
var api_key_back_button: Button = null
var last_ai_move_text := ""
var last_feedback := ""
var _applying_ai_move := false
var _ai_turn_queued := false
var _engine_game_started := false
var _ai_turn_serial := 0
var _ai_search_in_progress := false
var _waiting_for_ai_agent_reply := false
var _ai_agent_wait_serial := 0
var _ai_agent_wait_move_count := -1
var _ai_agent_analysis_queued := false
var _suppress_turn_flow := false
var _in_match := false
var _board_idle_transform := Transform3D.IDENTITY
var _board_flipped_transform := Transform3D.IDENTITY
var _board_reference_side: int = XiangqiConstants.RED
var _board_local_focus_point := Vector3.ZERO
var _board_camera_transform := Transform3D.IDENTITY
var _board_camera_fov := 0.0
var _notation_view_active := false
var _ai_io_view_active := false
var _match_view_ready := false
var _notation_initial_state: XiangqiState = null
var _match_initial_fen := XiangqiConstants.START_FEN
var _camera_tween: Tween = null
var _ai_io_entries: Array = []
var _ai_chat_waiting := false
var _ai_review_waiting := false
var _game_end_review_requested := false
var _pending_review_content := ""
var _pending_review_data := ""
var _game_end_status := ""
var _game_end_result := ""
var _game_end_review_generated := false
var _active_pikafish_threads: Array = []
var _joined_pikafish_threads: Array = []
var _notation_refresh_serial := 0
var radio_music_player: AudioStreamPlayer = null
var radio_music_playlist: PackedStringArray = []
var radio_music_track_names: PackedStringArray = []
var radio_music_track_index := 0
var radio_music_volume_level := RADIO_MUSIC_VOLUME_MEDIUM

func _enter_tree() -> void:
	if get_node_or_null("player") != null:
		return
	var player_instance := PLAYER_SCENE.instantiate()
	player_instance.name = "player"
	add_child(player_instance)

func _ready() -> void:
	super._ready()
	if !tree_exiting.is_connected(xiangqi_cleanup_runtime_audio):
		tree_exiting.connect(xiangqi_cleanup_runtime_audio, CONNECT_ONE_SHOT)
	if !get_tree().root.tree_exiting.is_connected(xiangqi_cleanup_runtime_audio):
		get_tree().root.tree_exiting.connect(xiangqi_cleanup_runtime_audio, CONNECT_ONE_SHOT)
	Ambient.change_environment_sound(load("res://assets/audio/52645__kstein1__white-noise.wav"))
	_setup_player_actor()
	_ensure_ai_adapter()
	_initialize_chess_ai()
	_initialize_api_key_ui()
	get_viewport().size_changed.connect(_update_match_ui_layout)
	_update_match_ui_layout()
	_capture_match_view_setup()
	board.interaction_enabled = false
	board.clear_selection()
	board.state_changed.connect(_on_board_state_changed)
	board.selection_changed.connect(_on_board_selection_changed)
	board.move_applied.connect(_on_board_move_applied)
	board.move_undone.connect(_on_board_move_undone)
	board.interaction_feedback.connect(_on_interaction_feedback)
	title[0x41] = "RADIO_MUSIC_TITLE"
	radio_music_ensure_audio_player()
	if ai_io_paper != null and ai_io_paper.has_signal("chat_submitted"):
		ai_io_paper.connect("chat_submitted", Callable(self, "_on_ai_io_chat_submitted"))
	undo_button.pressed.connect(undo_turn)
	leave_button.pressed.connect(leave_game)
	review_button.pressed.connect(_request_game_end_review_from_button)
	_show_match_ui(false)
	player.force_set_camera(main_camera)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		xiangqi_cleanup_runtime_audio()
		return
	if what != NOTIFICATION_TRANSLATION_CHANGED or !is_node_ready():
		return
	_refresh_match_ui()
	_refresh_api_key_status()
	if api_key_input != null:
		api_key_input.placeholder_text = tr("API_KEY_PLACEHOLDER")
	if ai_io_paper != null:
		if ai_io_paper.has_method("set_title_text"):
			ai_io_paper.set_title_text("XQ_AI_IO_TITLE")
		_refresh_ai_io_paper()

func _exit_tree() -> void:
	_prepare_for_scene_change()
	super._exit_tree()

func interact_start_menu() -> void:
	_prepare_for_scene_change()
	await super.interact_start_menu()

func interact_api_key() -> void:
	_show_api_key_screen()
	if api_key_screen != null and api_key_screen.visible:
		await api_key_screen_closed

func interact_radio_music() -> void:
	radio_music_ensure_audio_player()
	var should_close := false
	while !should_close:
		Dialog.push_selection(radio_music_options(), radio_music_status_text(), true, false)
		await Dialog.on_next
		match String(Dialog.selected):
			RADIO_MUSIC_OPTION_PREVIOUS:
				radio_music_step(-1)
			RADIO_MUSIC_OPTION_NEXT:
				radio_music_step(1)
			RADIO_MUSIC_OPTION_VOLUME_HIGH:
				radio_music_set_volume(RADIO_MUSIC_VOLUME_HIGH)
			RADIO_MUSIC_OPTION_VOLUME_MEDIUM:
				radio_music_set_volume(RADIO_MUSIC_VOLUME_MEDIUM)
			RADIO_MUSIC_OPTION_VOLUME_LOW:
				radio_music_set_volume(RADIO_MUSIC_VOLUME_LOW)
			RADIO_MUSIC_OPTION_PLAY:
				radio_music_start()
			RADIO_MUSIC_OPTION_STOP:
				radio_music_stop()
			_:
				should_close = true
	Dialog.clear()

func interact_pastor(custom_state: bool) -> void:
	var fen := start_fen
	if custom_state:
		var text_input_instance: TextInput = TextInput.create_text_input_instance("XQ_FEN_PROMPT", start_fen)
		add_child(text_input_instance)
		await text_input_instance.confirmed
		fen = text_input_instance.text.strip_edges()
		if fen.is_empty():
			return
		var custom_state_value := XiangqiState.new()
		if !XiangqiFen.apply_to_state(custom_state_value, fen):
			push_error("Invalid Xiangqi FEN: %s" % fen)
			return
		fen = custom_state_value.to_fen()

	Dialog.push_selection(
		[OPTION_PLAY_AS_RED, OPTION_PLAY_AS_BLACK, OPTION_PLAY_AS_RANDOM, OPTION_CANCEL],
		"",
		true,
		false
	)
	await Dialog.on_next
	if Dialog.selected == OPTION_CANCEL:
		return

	var selected_side := XiangqiConstants.RED
	match Dialog.selected:
		OPTION_PLAY_AS_BLACK:
			selected_side = XiangqiConstants.BLACK
		OPTION_PLAY_AS_RANDOM:
			selected_side = XiangqiConstants.RED if randi() % 2 == 0 else XiangqiConstants.BLACK
		_:
			selected_side = XiangqiConstants.RED

	Dialog.push_selection(
		[OPTION_XIANGQI_DIFFICULTY_STANDARD, OPTION_XIANGQI_DIFFICULTY_RELAX, OPTION_CANCEL],
		"",
		true,
		false
	)
	await Dialog.on_next
	if Dialog.selected == OPTION_CANCEL:
		return

	var selected_relax: bool = Dialog.selected == OPTION_XIANGQI_DIFFICULTY_RELAX
	await start_cafe_game(selected_side, fen, true, selected_relax)
	await xiangqi_game_finished

func start_cafe_game(side: int = XiangqiConstants.RED, fen: String = "", play_intro: bool = true, relax_ai: bool = false) -> void:
	human_side = side
	xiangqi_ai_relax = relax_ai
	var effective_fen := fen.strip_edges()
	if effective_fen.is_empty():
		effective_fen = start_fen
	var initial_state := XiangqiState.new()
	if !XiangqiFen.apply_to_state(initial_state, effective_fen):
		push_error("Invalid Xiangqi FEN: %s" % effective_fen)
		return
	var normalized_initial_fen := initial_state.to_fen()
	_cancel_pending_ai_turn()
	_engine_game_started = false
	_ai_review_waiting = false
	_game_end_review_requested = false
	_pending_review_content = ""
	_pending_review_data = ""
	_game_end_status = ""
	_game_end_result = ""
	_game_end_review_generated = false
	phase = MatchPhase.IDLE
	_in_match = true
	_set_api_key_screen_visible(false)
	_notation_view_active = false
	_ai_io_view_active = false
	_notation_refresh_serial += 1
	last_ai_move_text = ""
	last_feedback = ""
	_notation_initial_state = initial_state.duplicate()
	_match_initial_fen = normalized_initial_fen
	_restore_idle_board_transform()
	_restore_idle_board_camera()
	_apply_board_transform_for_side(human_side)

	if play_intro:
		var from: int = Chess.c64_to_x88(Chess.first_bit($chessboard.state.get_bit(player_king)))
		if from != 0x54:
			$chessboard.execute_move(Chess.create(from, 0x54, 0))
			await $chessboard.animation_finished
			history_document.set_state($chessboard.state)

	$chessboard.set_enabled(false)
	if has_node("chessboard/pieces/cheshire"):
		$chessboard/pieces/cheshire.set_position($chessboard.name_to_vector3("e2"))
		$chessboard/pieces/cheshire.set_rotation(Vector3(0, PI / 2, 0))
		$chessboard/pieces/cheshire.play_animation("thinking")

	board.set_state(initial_state)
	board.clear_selection()
	_refresh_notation_paper()
	_reset_ai_io_paper(_match_initial_fen)
	_refresh_ai_agent_banter_prompt_side()
	player.force_set_camera(board_camera)
	player.can_move = false
	_show_match_ui(true)
	_advance_turn_flow()
	_refresh_match_ui()

func undo_turn() -> bool:
	if !_in_match:
		return false
	if board == null or !board.can_undo():
		last_feedback = tr("XQ_NO_UNDO")
		_refresh_match_ui()
		return false
	if _is_checkmate_position():
		last_feedback = tr("XQ_NO_UNDO")
		_refresh_match_ui()
		return false
	if !_can_undo_now():
		last_feedback = tr("XQ_PIKAFISH_THINKING_WAIT")
		_refresh_match_ui()
		return false

	_cancel_pending_ai_turn()
	var undo_count := _get_undo_count_for_current_mode()
	var undone := 0
	var undone_move_texts: PackedStringArray = []
	_suppress_turn_flow = true
	for _index: int in undo_count:
		if !board.can_undo():
			break
		var move_to_undo: XiangqiMove = null
		if board.state != null and !board.state.move_history.is_empty():
			move_to_undo = board.state.move_history[board.state.move_history.size() - 1] as XiangqiMove
		var move_text := _format_move_for_io(move_to_undo) if move_to_undo != null else ""
		if board.undo_last_move(false):
			undone += 1
			if !move_text.is_empty():
				undone_move_texts.push_back(move_text)
	_suppress_turn_flow = false

	if undone == 0:
		last_feedback = tr("XQ_NO_UNDO")
		_refresh_match_ui()
		return false

	last_ai_move_text = ""
	last_feedback = tr("XQ_UNDONE")
	_queue_ai_agent_banter_after_undo(undone, ", ".join(undone_move_texts))
	_advance_turn_flow()
	_refresh_match_ui()
	return true

func leave_game() -> void:
	if !_in_match:
		return
	_archive_current_game_memory_on_leave()
	_cancel_pending_ai_turn()
	_wait_for_active_pikafish_threads()
	if ai_adapter != null and ai_adapter.has_method("stop_engine"):
		ai_adapter.stop_engine()
	_engine_game_started = false
	_ai_search_in_progress = false
	phase = MatchPhase.IDLE
	_in_match = false
	_set_api_key_screen_visible(false)
	_notation_view_active = false
	_ai_io_view_active = false
	_notation_refresh_serial += 1
	last_feedback = ""
	last_ai_move_text = ""
	_notation_initial_state = null
	_match_initial_fen = XiangqiConstants.START_FEN
	_ai_chat_waiting = false
	_ai_review_waiting = false
	_game_end_review_requested = false
	_pending_review_content = ""
	_pending_review_data = ""
	_game_end_status = ""
	_game_end_result = ""
	_game_end_review_generated = false
	board.interaction_enabled = false
	board.clear_selection()
	_refresh_notation_paper()
	_ai_io_entries.clear()
	if ai_io_paper != null and ai_io_paper.has_method("clear_entries"):
		ai_io_paper.clear_entries()
	else:
		_refresh_ai_io_paper()
	_restore_idle_board_transform()
	_restore_idle_board_camera()
	_show_match_ui(false)
	player.force_set_camera(main_camera)
	player.can_move = true
	$chessboard.set_enabled(true)
	if has_node("chessboard/pieces/cheshire"):
		$chessboard/pieces/cheshire.play_animation("battle_idle")
		$chessboard/pieces/cheshire.set_position($chessboard.name_to_vector3("e3"))
	xiangqi_game_finished.emit()

func _archive_current_game_memory_on_leave() -> void:
	if _game_end_review_requested:
		return
	if board == null or board.state == null:
		return
	if chess_ai_wrapper == null:
		_initialize_chess_ai()
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return

	var status := XiangqiRules.get_position_status(board.state)
	var result := _game_result_text(status) if status == "checkmate" or status == "stalemate" else ""
	if result.is_empty():
		result = tr("GAME_RESULT_LEFT")

	var session: Dictionary = chess_ai_wrapper.create_game_session(board.state, human_side, ai_enabled, _notation_initial_state)
	session["GameStatus"] = tr("GAME_STATUS_FINISHED")
	session["GameResult"] = result
	session["GameEndStatus"] = status
	session["LeftByPlayer"] = true
	chess_ai_wrapper.archive_current_game_memory(session, result)

func _prepare_for_scene_change() -> void:
	_cancel_pending_ai_turn()
	_waiting_for_ai_agent_reply = false
	_ai_agent_analysis_queued = false
	_ai_agent_wait_serial += 1
	_ai_agent_wait_move_count = -1
	_ai_chat_waiting = false
	_ai_review_waiting = false
	_game_end_review_requested = false
	_pending_review_content = ""
	_pending_review_data = ""
	_ai_search_in_progress = false
	_ai_turn_queued = false
	_applying_ai_move = false
	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null
	if board != null:
		board.interaction_enabled = false
		board.clear_selection()
	if ai_adapter != null and ai_adapter.has_method("stop_engine"):
		ai_adapter.stop_engine()
	xiangqi_cleanup_runtime_audio()
	_wait_for_active_pikafish_threads()

func xiangqi_cleanup_runtime_audio() -> void:
	radio_music_cleanup_audio_player()
	if is_instance_valid(Ambient):
		Ambient.clear_environment_sound()

func radio_music_ensure_audio_player() -> void:
	radio_music_load_playlist()
	if radio_music_player == null:
		radio_music_player = AudioStreamPlayer.new()
		radio_music_player.name = "radio_music_player"
		radio_music_player.bus = &"Ambient"
		add_child(radio_music_player)
		radio_music_player.finished.connect(radio_music_on_finished)
	radio_music_apply_volume()
	if radio_music_player.stream == null and !radio_music_playlist.is_empty():
		radio_music_play_track(radio_music_track_index)

func radio_music_cleanup_audio_player() -> void:
	if is_instance_valid(radio_music_player):
		if radio_music_player.finished.is_connected(radio_music_on_finished):
			radio_music_player.finished.disconnect(radio_music_on_finished)
		radio_music_player.stop()
		radio_music_player.stream = null
		if radio_music_player.get_parent() != null:
			radio_music_player.get_parent().remove_child(radio_music_player)
		radio_music_player.free()
	radio_music_player = null

func radio_music_load_playlist() -> void:
	if !radio_music_playlist.is_empty():
		return
	var dir := DirAccess.open(RADIO_MUSIC_DIRECTORY)
	if dir == null:
		return
	var files := PackedStringArray()
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var music_file_name := radio_music_normalize_file_name(file_name)
		if music_file_name.is_empty():
			continue
		if RADIO_MUSIC_EXCLUDED_FILES.has(music_file_name):
			continue
		if files.has(music_file_name):
			continue
		files.push_back(music_file_name)
	dir.list_dir_end()
	files.sort()
	for file_name: String in files:
		radio_music_playlist.push_back("%s/%s" % [RADIO_MUSIC_DIRECTORY, file_name])
		radio_music_track_names.push_back(file_name.get_basename())

func radio_music_normalize_file_name(file_name: String) -> String:
	if file_name.get_extension().to_lower() == "mp3":
		return file_name
	if file_name.to_lower().ends_with(RADIO_MUSIC_IMPORT_SUFFIX):
		return file_name.substr(0, file_name.length() - ".import".length())
	return ""

func radio_music_play_track(track_index: int) -> void:
	if radio_music_player == null:
		radio_music_ensure_audio_player()
	if radio_music_player == null or radio_music_playlist.is_empty():
		return
	radio_music_track_index = posmod(track_index, radio_music_playlist.size())
	var stream := radio_music_load_stream(radio_music_playlist[radio_music_track_index])
	if stream == null:
		radio_music_player.stream = null
		return
	radio_music_player.stream = stream
	radio_music_apply_volume()
	radio_music_player.play()

func radio_music_load_stream(path: String) -> AudioStream:
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		stream = radio_music_load_mp3_from_file(path)
	if stream == null:
		return null
	var duplicate_stream := stream.duplicate() as AudioStream
	if duplicate_stream != null:
		stream = duplicate_stream
	var mp3_stream := stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = false
	return stream

func radio_music_load_mp3_from_file(path: String) -> AudioStream:
	if path.get_extension().to_lower() != "mp3":
		return null
	if !FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var stream := AudioStreamMP3.new()
	stream.data = file.get_buffer(int(file.get_length()))
	stream.loop = false
	return stream

func radio_music_on_finished() -> void:
	radio_music_step(1)

func radio_music_step(delta: int) -> void:
	if radio_music_playlist.is_empty():
		return
	radio_music_play_track(radio_music_track_index + delta)

func radio_music_set_volume(level: String) -> void:
	radio_music_volume_level = level
	radio_music_apply_volume()

func radio_music_stop() -> void:
	if radio_music_player != null:
		radio_music_player.stop()

func radio_music_start() -> void:
	radio_music_ensure_audio_player()
	if radio_music_player == null:
		return
	if radio_music_is_playing():
		return
	if radio_music_player.stream == null:
		radio_music_play_track(radio_music_track_index)
		return
	radio_music_apply_volume()
	radio_music_player.play()

func radio_music_is_playing() -> bool:
	return radio_music_player != null and radio_music_player.playing

func radio_music_apply_volume() -> void:
	if radio_music_player == null:
		return
	match radio_music_volume_level:
		RADIO_MUSIC_VOLUME_HIGH:
			radio_music_player.volume_db = -2.0
		RADIO_MUSIC_VOLUME_LOW:
			radio_music_player.volume_db = -20.0
		_:
			radio_music_player.volume_db = -10.0

func radio_music_volume_text() -> String:
	match radio_music_volume_level:
		RADIO_MUSIC_VOLUME_HIGH:
			return tr("RADIO_MUSIC_VOLUME_HIGH")
		RADIO_MUSIC_VOLUME_LOW:
			return tr("RADIO_MUSIC_VOLUME_LOW")
		_:
			return tr("RADIO_MUSIC_VOLUME_MEDIUM")

func radio_music_current_track_name() -> String:
	if radio_music_track_names.is_empty():
		return tr("RADIO_MUSIC_NO_TRACK")
	return radio_music_track_names[clampi(radio_music_track_index, 0, radio_music_track_names.size() - 1)]

func radio_music_status_text() -> String:
	if !radio_music_is_playing():
		return "%s\n%s" % [
			tr("RADIO_MUSIC_STATUS_STOPPED"),
			tr("RADIO_MUSIC_STATUS_VOLUME") % radio_music_volume_text(),
		]
	return "%s\n%s" % [
		tr("RADIO_MUSIC_STATUS_PLAYING") % radio_music_current_track_name(),
		tr("RADIO_MUSIC_STATUS_VOLUME") % radio_music_volume_text(),
	]

func radio_music_options() -> PackedStringArray:
	return PackedStringArray([
		RADIO_MUSIC_OPTION_PREVIOUS,
		RADIO_MUSIC_OPTION_NEXT,
		RADIO_MUSIC_OPTION_VOLUME_HIGH,
		RADIO_MUSIC_OPTION_VOLUME_MEDIUM,
		RADIO_MUSIC_OPTION_VOLUME_LOW,
		RADIO_MUSIC_OPTION_STOP if radio_music_is_playing() else RADIO_MUSIC_OPTION_PLAY,
		RADIO_MUSIC_OPTION_EXIT,
	])

func _unhandled_input(event: InputEvent) -> void:
	if _is_api_key_screen_visible():
		var api_key_event := event as InputEventKey
		if api_key_event != null and api_key_event.pressed and !api_key_event.echo and api_key_event.keycode == KEY_ESCAPE:
			_hide_api_key_screen()
		get_viewport().set_input_as_handled()
		return
	if !_in_match:
		return
	var active_camera := _get_active_scene_camera()
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed:
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and _is_paper_view_active():
			_exit_paper_view()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if _notation_view_active:
				if notation_paper != null and notation_paper.handle_click(active_camera, mouse_event.position):
					get_viewport().set_input_as_handled()
					return
			elif _ai_io_view_active:
				if ai_io_paper != null and ai_io_paper.handle_click(active_camera, mouse_event.position):
					get_viewport().set_input_as_handled()
					return
			elif notation_paper != null and notation_paper.contains_screen_point(active_camera, mouse_event.position):
				_enter_notation_view()
				get_viewport().set_input_as_handled()
				return
			elif ai_io_paper != null and ai_io_paper.contains_screen_point(active_camera, mouse_event.position):
				_enter_ai_io_view()
				get_viewport().set_input_as_handled()
				return
	var key_event := event as InputEventKey
	if key_event == null or !key_event.pressed or key_event.echo:
		return
	if _ai_io_view_active and ai_io_paper != null and ai_io_paper.has_method("handle_key_event"):
		if bool(ai_io_paper.handle_key_event(key_event)):
			get_viewport().set_input_as_handled()
			return
	if key_event.keycode in [KEY_ESCAPE, KEY_Q]:
		if _is_paper_view_active():
			_exit_paper_view()
		else:
			leave_game()
		get_viewport().set_input_as_handled()
		return
	if _is_paper_view_active():
		if key_event.keycode in [KEY_PAGEUP, KEY_BRACKETLEFT]:
			if _turn_active_paper_page(-1):
				get_viewport().set_input_as_handled()
			return
		if key_event.keycode in [KEY_PAGEDOWN, KEY_BRACKETRIGHT]:
			if _turn_active_paper_page(1):
				get_viewport().set_input_as_handled()
			return
		return
	if key_event.keycode in [KEY_U, KEY_Z, KEY_BACKSPACE]:
		if undo_turn():
			get_viewport().set_input_as_handled()
		return
	if phase == MatchPhase.AI_THINKING:
		return

func _setup_player_actor() -> void:
	var cheshire_by := int(get_meta("by"))
	if $chessboard.state.has_piece(cheshire_by):
		chessboard.button_input_pointer = cheshire_by
		return

	var cheshire_instance: Actor = CHESHIRE_SCENE.instantiate()
	cheshire_instance.position = $chessboard.x88_to_vector3(cheshire_by)
	$chessboard.state.add_piece(cheshire_by, player_king)
	$chessboard.add_piece_instance(cheshire_instance, cheshire_by)
	chessboard.button_input_pointer = cheshire_by
	$pastor.play_animation("thinking")
	title[0x54] = "CHAR_YULAN"
	title[0x55] = "CHAR_YULAN"

func _filter_ready_to_move_selection(selection: PackedStringArray) -> PackedStringArray:
	var filtered := PackedStringArray()
	for option in selection:
		if option == "SELECTION_SETTINGS" or option == "SELECTION_STATUS":
			continue
		filtered.push_back(option)
	return filtered

func _ensure_ai_adapter() -> void:
	if ai_adapter != null:
		return
	ai_adapter = get_node_or_null("pikafish_adapter")
	if ai_adapter == null:
		ai_adapter = PikafishAdapterScript.new()
		ai_adapter.name = "pikafish_adapter"
		add_child(ai_adapter)
	if ai_adapter.has_signal("engine_error"):
		ai_adapter.engine_error.connect(_on_ai_engine_error)

func _initialize_chess_ai() -> void:
	if chess_ai_wrapper != null:
		return
	chess_ai_wrapper = ChessAIWrapper.new()
	chess_ai_wrapper.name = "chess_ai_wrapper"
	chess_ai_wrapper.ai_response.connect(_on_chess_ai_response)
	chess_ai_wrapper.review_generated.connect(_on_chess_ai_review_generated)
	add_child(chess_ai_wrapper)
	_refresh_ai_agent_banter_prompt_side()

func _refresh_ai_agent_banter_prompt_side() -> void:
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return
	chess_ai_wrapper.set_banter_player_side(human_side)
	if chess_ai_wrapper.has_method("set_chat_player_side"):
		chess_ai_wrapper.set_chat_player_side(human_side)
	if chess_ai_wrapper.has_method("set_review_player_side"):
		chess_ai_wrapper.set_review_player_side(human_side)

func _initialize_api_key_ui() -> void:
	api_key_button = get_node_or_null("ui_overlay/bottom_bar/api_key_button") as Button
	api_key_screen = get_node_or_null("ui_overlay/api_key_screen") as Control
	api_key_input = get_node_or_null("ui_overlay/api_key_screen/panel/api_key_input") as LineEdit
	api_key_status_label = get_node_or_null("ui_overlay/api_key_screen/panel/status_label") as Label
	api_key_save_button = get_node_or_null("ui_overlay/api_key_screen/panel/save_button") as Button
	api_key_clear_button = get_node_or_null("ui_overlay/api_key_screen/panel/clear_button") as Button
	api_key_back_button = get_node_or_null("ui_overlay/api_key_screen/panel/back_button") as Button

	if api_key_button != null:
		api_key_button.pressed.connect(_show_api_key_screen)
	if api_key_save_button != null:
		api_key_save_button.pressed.connect(_save_api_key_from_input)
	if api_key_clear_button != null:
		api_key_clear_button.pressed.connect(_clear_runtime_api_key)
	if api_key_back_button != null:
		api_key_back_button.pressed.connect(_hide_api_key_screen)
	if api_key_input != null:
		api_key_input.placeholder_text = tr("API_KEY_PLACEHOLDER")
		api_key_input.text_submitted.connect(_on_api_key_input_submitted)

	_set_api_key_screen_visible(false)
	_refresh_api_key_status()

func _show_api_key_screen() -> void:
	_set_api_key_screen_visible(true)
	_refresh_ai_agent_banter_prompt_side()
	if player != null:
		player.can_move = false
	if board != null:
		board.interaction_enabled = false
	if api_key_input != null:
		api_key_input.text = ""
		api_key_input.grab_focus()
	_refresh_api_key_status()

func _hide_api_key_screen() -> void:
	_set_api_key_screen_visible(false)
	if api_key_input != null:
		api_key_input.release_focus()
	if player != null:
		player.can_move = !_in_match
	_sync_board_interaction()

func _set_api_key_screen_visible(should_show: bool) -> void:
	if api_key_screen == null:
		return
	var was_visible := api_key_screen.visible
	api_key_screen.visible = should_show
	if was_visible and !should_show:
		api_key_screen_closed.emit()

func _is_api_key_screen_visible() -> bool:
	return api_key_screen != null and api_key_screen.visible

func _save_api_key_from_input() -> void:
	if api_key_input == null:
		return
	var api_key := api_key_input.text.strip_edges()
	if api_key.is_empty():
		_set_api_key_status(tr("API_KEY_EMPTY"))
		return
	if chess_ai_wrapper == null:
		_initialize_chess_ai()
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		_set_api_key_status(tr("MATCH_AI_UNAVAILABLE"))
		return
	if !chess_ai_wrapper.set_api_key(api_key):
		_set_api_key_status(tr("API_KEY_SAVE_FAILED"))
		return
	api_key_input.text = ""
	_set_api_key_status(tr("API_KEY_SAVED"))

func _clear_runtime_api_key() -> void:
	if chess_ai_wrapper == null:
		_initialize_chess_ai()
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		_set_api_key_status(tr("MATCH_AI_UNAVAILABLE"))
		return
	if !chess_ai_wrapper.clear_api_key():
		_set_api_key_status(tr("API_KEY_CLEAR_FAILED"))
		return
	_set_api_key_status(tr("API_KEY_CLEARED"))

func _on_api_key_input_submitted(_text: String) -> void:
	_save_api_key_from_input()

func _refresh_api_key_status() -> void:
	if chess_ai_wrapper != null and chess_ai_wrapper.has_saved_api_key():
		_set_api_key_status(tr("API_KEY_LOADED"))
	elif chess_ai_wrapper != null and chess_ai_wrapper.has_api_key():
		_set_api_key_status(tr("API_KEY_READY"))
	else:
		_set_api_key_status(tr("API_KEY_WAITING"))

func _set_api_key_status(text: String) -> void:
	if api_key_status_label != null:
		api_key_status_label.text = text

func _on_board_state_changed(_state) -> void:
	_refresh_match_ui()

func _on_board_selection_changed(_square_index: int, _square_name: String) -> void:
	_refresh_match_ui()

func _on_board_move_applied(move: XiangqiMove) -> void:
	if _applying_ai_move:
		last_ai_move_text = move.to_coordinate_string()
		last_feedback = tr("XQ_PIKAFISH_MOVED") % last_ai_move_text
	else:
		last_feedback = tr("XQ_PLAYER_MOVED") % move.to_coordinate_string()
	if _applying_ai_move:
		_refresh_notation_paper()
	else:
		_queue_notation_paper_refresh_after_player_move()
		_queue_ai_agent_analysis_after_move(move)
	_advance_turn_flow()
	_refresh_match_ui()

func _on_board_move_undone(_move: XiangqiMove) -> void:
	last_ai_move_text = ""
	_ai_review_waiting = false
	_game_end_review_requested = false
	_pending_review_content = ""
	_pending_review_data = ""
	_game_end_status = ""
	_game_end_result = ""
	_game_end_review_generated = false
	if _in_match:
		_append_ai_io_entry("system", tr("XQ_UNDO_ONE"))
	_refresh_notation_paper()
	if _suppress_turn_flow:
		return
	_advance_turn_flow()
	_refresh_match_ui()

func _on_board_move_logged(move: XiangqiMove) -> void:
	var move_text := _format_move_for_io(move)
	if _applying_ai_move:
		_append_ai_io_entry("ai", tr("XQ_OUTPUT_MOVE") % move_text)
	else:
		_append_ai_io_entry("player", tr("XQ_INPUT_MOVE") % move_text)

func _on_interaction_feedback(message: String) -> void:
	last_feedback = message
	_refresh_match_ui()

func _advance_turn_flow() -> void:
	if !_in_match or board == null or board.state == null:
		phase = MatchPhase.IDLE
		_sync_board_interaction()
		return

	var status := XiangqiRules.get_position_status(board.state)
	if status == "checkmate" or status == "stalemate":
		phase = MatchPhase.GAME_OVER
		_sync_board_interaction()
		return

	if ai_enabled and _is_ai_turn():
		_begin_ai_turn()
	else:
		phase = MatchPhase.PLAYER_TURN
		_sync_board_interaction()

func _begin_ai_turn(immediate: bool = false) -> void:
	if _waiting_for_ai_agent_reply:
		phase = MatchPhase.AI_THINKING
		board.clear_selection()
		_sync_board_interaction()
		_refresh_match_ui(tr("XQ_AI_AGENT_REPLYING"))
		return
	if _ai_turn_queued or phase == MatchPhase.AI_THINKING:
		return
	phase = MatchPhase.AI_THINKING
	board.clear_selection()
	_sync_board_interaction()
	_refresh_match_ui(tr("XQ_PIKAFISH_THINKING"))
	_ai_turn_queued = true
	_ai_turn_serial += 1
	call_deferred("_run_ai_turn", _ai_turn_serial, immediate)

func _run_ai_turn(turn_serial: int, _immediate: bool = false) -> void:
	_ai_turn_queued = false
	if turn_serial != _ai_turn_serial:
		return
	if !_in_match or board == null or board.state == null or !ai_enabled or !_is_ai_turn():
		_advance_turn_flow()
		return

	_refresh_match_ui(tr("XQ_PIKAFISH_THINKING"))
	if false:
		pass
		if false:
			_handle_ai_failure(tr("XQ_PIKAFISH_NEW_GAME_FAILED"))
			return
		_engine_game_started = true

	var search_state: XiangqiState = board.state.duplicate()
	_ai_search_in_progress = true
	var search_result: Dictionary = await _request_ai_bestmove_threaded(
		search_state,
		_effective_ai_movetime_ms(),
		_effective_ai_search_depth(),
		_effective_ai_skill_level()
	)
	_ai_search_in_progress = false
	if turn_serial != _ai_turn_serial or !_in_match:
		return

	if !bool(search_result.get("ok", false)):
		var error_message: String = String(search_result.get("error", ""))
		if error_message.is_empty():
			error_message = "Pikafish did not return a usable move."
		_handle_ai_failure(error_message)
		return

	var ai_move := search_result.get("move") as XiangqiMove
	if ai_move == null:
		_handle_ai_failure(tr("XQ_PIKAFISH_NO_MOVE"))
		return
	if !XiangqiRules.is_legal_move(board.state, ai_move):
		_handle_ai_failure(tr("XQ_PIKAFISH_ILLEGAL_MOVE") % ai_move.to_coordinate_string())
		return

	_applying_ai_move = true
	var applied := board.apply_move(ai_move)
	_applying_ai_move = false
	_refresh_match_ui()
	if !applied:
		_handle_ai_failure(tr("XQ_PIKAFISH_APPLY_FAILED") % ai_move.to_coordinate_string())
		return

func _handle_ai_failure(message: String) -> void:
	_applying_ai_move = false
	_ai_search_in_progress = false
	last_feedback = message
	_append_ai_io_entry("ai", tr("XQ_OUTPUT_ERROR") % message)
	phase = MatchPhase.PLAYER_TURN
	_sync_board_interaction()
	_refresh_match_ui()

func _on_ai_engine_error(message: String) -> void:
	last_feedback = message
	_append_ai_io_entry("ai", tr("XQ_ENGINE_ERROR") % message)
	_refresh_match_ui()

func _get_undo_count_for_current_mode() -> int:
	if !ai_enabled:
		return 1
	if _is_human_turn() and board != null and board.state != null and board.state.move_history.size() >= 2:
		return 2
	return 1

func _can_undo_now() -> bool:
	if board == null or !board.can_undo():
		return false
	if _is_checkmate_position():
		return false
	if _ai_search_in_progress or _ai_turn_queued or _applying_ai_move or _waiting_for_ai_agent_reply or _ai_review_waiting or _game_end_review_requested:
		return false
	if !ai_enabled:
		return true
	if phase == MatchPhase.AI_THINKING or _is_ai_turn():
		return false
	return board.state != null and board.state.move_history.size() >= 2

func _is_checkmate_position() -> bool:
	if board == null or board.state == null:
		return false
	var status := XiangqiRules.get_position_status(board.state)
	return status == "checkmate" or status == "stalemate"

func _cancel_pending_ai_turn() -> void:
	_cancel_ai_agent_reply_wait()
	_ai_turn_serial += 1
	_ai_turn_queued = false
	_ai_search_in_progress = false

func _is_ai_turn() -> bool:
	return board != null and board.state != null and board.state.side_to_move != human_side

func _is_human_turn() -> bool:
	return !ai_enabled or (board != null and board.state != null and board.state.side_to_move == human_side)

func _sync_board_interaction() -> void:
	if board == null:
		return
	board.interaction_enabled = _in_match and !_is_paper_view_active() and phase == MatchPhase.PLAYER_TURN and _is_human_turn()

func _refresh_match_ui(feedback: String = "") -> void:
	if !_in_match:
		_show_match_ui(false)
		return
	if _notation_view_active:
		_show_match_ui(true)
		top_label.text = tr("XQ_MOVE_SHEET_HELP")
		_refresh_bottom_actions()
		return
	if _ai_io_view_active:
		_show_match_ui(true)
		top_label.text = tr("XQ_AI_IO_TITLE")
		_refresh_bottom_actions()
		return
	var effective_feedback := feedback if !feedback.is_empty() else last_feedback
	_show_match_ui(true)
	top_label.text = _top_prompt_text()
	_refresh_bottom_actions()
	if !effective_feedback.is_empty() and phase != MatchPhase.AI_THINKING:
		top_label.text = "%s\n%s" % [_top_prompt_text(), effective_feedback]

func _refresh_bottom_actions() -> void:
	undo_button.text = tr("MATCH_UNDO")
	undo_button.disabled = !_can_undo_now()
	undo_button.modulate = Color(0.45, 0.45, 0.45, 1.0) if undo_button.disabled else Color.WHITE
	leave_button.text = tr("MATCH_LEAVE_GAME")
	leave_button.disabled = false
	review_button.visible = _should_show_game_end_review_button()
	if review_button.visible:
		if _ai_review_waiting:
			review_button.text = tr("MATCH_REVIEW_GENERATING")
		elif _game_end_review_generated:
			review_button.text = tr("MATCH_REVIEW_GENERATED")
		else:
			review_button.text = tr("MATCH_GENERATE_REVIEW")
		review_button.disabled = _ai_review_waiting
		review_button.modulate = Color(0.45, 0.45, 0.45, 1.0) if review_button.disabled else Color.WHITE
	if api_key_button != null:
		api_key_button.text = tr("MATCH_API_KEY")
		api_key_button.disabled = false

func _should_show_game_end_review_button() -> bool:
	return phase == MatchPhase.GAME_OVER and board != null and board.state != null

func _show_match_ui(should_show: bool) -> void:
	top_bar.visible = should_show
	bottom_bar.visible = should_show

func _update_match_ui_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var insets: Vector4 = UISafeArea.get_content_insets(get_viewport())
	var base_height: float = clampf(viewport_size.y * 0.08, 66.0, 92.0)
	var top_height: float = insets.y + base_height
	var bottom_height: float = insets.w + base_height

	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	top_bar.offset_left = 0.0
	top_bar.offset_top = 0.0
	top_bar.offset_right = 0.0
	top_bar.offset_bottom = top_height
	top_label.offset_top = insets.y
	top_label.offset_bottom = 0.0

	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, false)
	bottom_bar.offset_left = 0.0
	bottom_bar.offset_top = -bottom_height
	bottom_bar.offset_right = 0.0
	bottom_bar.offset_bottom = 0.0
	for control: Control in [undo_button, leave_button, review_button]:
		control.offset_top = 0.0
		control.offset_bottom = -insets.w
	if api_key_button != null:
		api_key_button.offset_top = 0.0
		api_key_button.offset_bottom = -insets.w

func _turn_active_paper_page(delta: int) -> bool:
	if _notation_view_active:
		if notation_paper == null or !notation_paper.can_turn_page(delta):
			return false
		return notation_paper.turn_page(delta)
	if _ai_io_view_active:
		if ai_io_paper == null or !ai_io_paper.can_turn_page(delta):
			return false
		return ai_io_paper.turn_page(delta)
	return false

func _queue_notation_paper_refresh_after_player_move() -> void:
	_notation_refresh_serial += 1
	var refresh_serial := _notation_refresh_serial
	call_deferred("_refresh_notation_paper_after_player_move", refresh_serial)

func _refresh_notation_paper_after_player_move(refresh_serial: int) -> void:
	var delay: float = maxf(0.0, player_move_notation_refresh_delay_sec)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	else:
		await get_tree().process_frame
	if refresh_serial != _notation_refresh_serial:
		return
	_refresh_notation_paper()

func _refresh_notation_paper() -> void:
	if notation_paper == null:
		return
	if !_in_match or _notation_initial_state == null or board == null or board.state == null:
		notation_paper.clear_entries()
		return
	notation_paper.set_entries(XiangqiNotation.build_move_rows(_notation_initial_state, board.state.move_history))

func _reset_ai_io_paper(fen: String) -> void:
	_ai_io_entries.clear()
	_ai_chat_waiting = false
	_ai_review_waiting = false
	_pending_review_content = ""
	_pending_review_data = ""
	if ai_io_paper != null and ai_io_paper.has_method("clear_entries"):
		ai_io_paper.clear_entries()
	else:
		_refresh_ai_io_paper()
	if ai_io_paper != null and ai_io_paper.has_method("set_title_text"):
		ai_io_paper.set_title_text("XQ_AI_IO_TITLE")
	_append_ai_io_entry("system", tr("XQ_GAME_STARTED") % _side_text(human_side))
	if !fen.is_empty() and fen != start_fen:
		_append_ai_io_entry("player", tr("XQ_INPUT_FEN") % fen)

func _append_ai_io_entry(role: String, text: String) -> void:
	if !["ai_agent", "review", "error", "system", "player", "ai"].has(role):
		return
	var clean_text := text.strip_edges()
	if ["ai_agent", "review", "error", "ai"].has(role):
		clean_text = _clean_ai_io_visible_text(clean_text)
		if _is_internal_ai_io_text(clean_text):
			return
	if clean_text.is_empty():
		return
	_ai_io_entries.push_back({
		"role": role,
		"text": clean_text,
	})
	_refresh_ai_io_paper()

func _refresh_ai_io_paper() -> void:
	if ai_io_paper == null:
		return
	ai_io_paper.set_entries(_ai_io_entries)

func _set_ai_io_response(role: String, text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		_refresh_ai_io_paper()
		return
	_append_ai_io_entry(role, clean_text)

func _notify_ai_about_game_end(status: String) -> void:
	if _game_end_review_requested:
		return
	if chess_ai_wrapper == null:
		_initialize_chess_ai()
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		last_feedback = tr("MATCH_AI_UNAVAILABLE")
		_refresh_match_ui()
		return
	if !chess_ai_wrapper.has_api_key():
		last_feedback = tr("MATCH_API_KEY_REQUIRED")
		_refresh_match_ui()
		return
	if board == null or board.state == null:
		return

	var session: Dictionary = chess_ai_wrapper.create_game_session(board.state, human_side, ai_enabled, _notation_initial_state)
	var result := _game_result_text(status)
	_game_end_status = status
	_game_end_result = result
	_game_end_review_generated = false
	session["GameStatus"] = tr("GAME_STATUS_FINISHED")
	session["GameResult"] = result
	_game_end_review_requested = true
	_ai_review_waiting = true
	last_feedback = tr("MATCH_REVIEW_GENERATING_STATUS")
	_refresh_match_ui()
	chess_ai_wrapper.send_game_ended(session, result)

func _request_game_end_review_from_button() -> void:
	if board == null or board.state == null:
		return
	if !_should_show_game_end_review_button():
		last_feedback = tr("XQ_REVIEW_NOT_CHECKMATE")
		_refresh_match_ui()
		return
	if _ai_review_waiting:
		last_feedback = tr("MATCH_REVIEW_GENERATING_STATUS")
		_refresh_match_ui()
		return
	if _game_end_review_generated:
		_enter_ai_io_view()
		_refresh_match_ui()
		return
	var status := XiangqiRules.get_position_status(board.state)
	if status.is_empty():
		last_feedback = tr("MATCH_REVIEW_NO_CHECKMATE")
		_refresh_match_ui()
		return
	_notify_ai_about_game_end(status)

func _game_result_text(status: String) -> String:
	if (status == "checkmate" or status == "stalemate") and board != null and board.state != null:
		return tr("GAME_RESULT_RED_WIN") if board.state.side_to_move == XiangqiConstants.BLACK else tr("GAME_RESULT_BLACK_WIN")
	return tr("XQ_GAME_OVER")

func _set_ai_io_chat_response(role: String, text: String) -> void:
	if ai_io_paper == null or !ai_io_paper.has_method("set_chat_response"):
		return
	var clean_text := _clean_ai_io_visible_text(text)
	if clean_text.is_empty() or _is_internal_ai_io_text(clean_text):
		return
	ai_io_paper.set_chat_response(role, clean_text)

func _format_ai_response_display_text(response_type: String, content: String) -> String:
	var clean_type := response_type.strip_edges()
	var clean_content := _clean_ai_io_visible_text(content)
	if clean_content.is_empty():
		return ""
	var lower_type := clean_type.to_lower()
	if lower_type == "banter":
		return "[%s]\n%s" % [_ai_response_type_label(lower_type), clean_content]
	if lower_type == "review":
		return "[%s]\n%s" % [clean_type, clean_content]
	return clean_content

func _ai_response_type_label(lower_type: String) -> String:
	if lower_type == "banter":
		return "搭话"
	return lower_type

func _clean_ai_io_visible_text(text: String) -> String:
	var result := text.strip_edges()
	while true:
		var lower_result := result.to_lower()
		var think_start := lower_result.find("<think>")
		if think_start < 0:
			break
		var think_end := lower_result.find("</think>", think_start)
		if think_end < 0:
			result = result.substr(0, think_start).strip_edges()
			break
		result = (result.substr(0, think_start) + result.substr(think_end + "</think>".length())).strip_edges()
	return result.strip_edges()

func _is_internal_ai_io_text(text: String) -> bool:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return false
	var lower_text := clean_text.to_lower()
	if ["no_response", "none", "null"].has(lower_text):
		return true
	if AI_AGENT_TOOL_NAMES.has(lower_text):
		return true
	if clean_text == tr("XQ_AI_THINKING_ENTRY") or clean_text == "Thinking about the next move.":
		return true
	if lower_text.begins_with("tool_call") or lower_text.begins_with("agent selected tool"):
		return true
	return false

func _on_ai_io_chat_submitted(message: String) -> void:
	var clean_text := message.strip_edges()
	if clean_text.is_empty():
		return
	_ai_chat_waiting = true
	if chess_ai_wrapper == null:
		_initialize_chess_ai()
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		_ai_chat_waiting = false
		_set_ai_io_chat_response("chat_error", tr("MATCH_AI_UNAVAILABLE"))
		return

	var session: Dictionary = {}
	if board != null and board.state != null:
		session = chess_ai_wrapper.create_game_session(board.state, human_side, ai_enabled, _notation_initial_state)
	else:
		session = {
			"AIEnabled": ai_enabled,
			"HumanSide": human_side,
			"SessionId": str(Time.get_unix_time_from_system()),
		}
	_apply_game_end_context_to_chat_session(session)
	chess_ai_wrapper.send_player_message(clean_text, session)

func _apply_game_end_context_to_chat_session(session: Dictionary) -> void:
	if !_game_end_review_generated:
		return
	var result := _game_end_result
	var status := _game_end_status
	if result.is_empty() and board != null and board.state != null:
		status = XiangqiRules.get_position_status(board.state)
		result = _game_result_text(status)
	if result.is_empty():
		return
	session["GameStatus"] = tr("GAME_STATUS_FINISHED")
	session["GameResult"] = result
	session["GameEndStatus"] = status
	session["HumanResult"] = _human_result_text(result)
	session["ReviewGenerated"] = true

func _human_result_text(result: String) -> String:
	if result == tr("GAME_RESULT_DRAW"):
		return tr("GAME_RESULT_DRAW")
	if result == tr("GAME_RESULT_RED_WIN"):
		return tr("HUMAN_RESULT_WIN") if human_side == XiangqiConstants.RED else tr("HUMAN_RESULT_LOSS")
	if result == tr("GAME_RESULT_BLACK_WIN"):
		return tr("HUMAN_RESULT_WIN") if human_side == XiangqiConstants.BLACK else tr("HUMAN_RESULT_LOSS")
	return ""

func _queue_ai_agent_analysis_after_move(move: XiangqiMove) -> void:
	if move == null or _applying_ai_move:
		return
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return
	if !chess_ai_wrapper.has_api_key():
		return
	if board == null or board.state == null:
		return
	var expected_move_count := board.state.move_history.size() if board != null and board.state != null else -1
	var wait_serial := -1
	if _should_gate_ai_agent_before_pikafish():
		_begin_ai_agent_reply_wait()
		_ai_agent_analysis_queued = true
		wait_serial = _ai_agent_wait_serial
	call_deferred("_notify_ai_about_move_after_animation", move.duplicate(), expected_move_count, wait_serial)

func _notify_ai_about_move_after_animation(move: XiangqiMove, expected_move_count: int, wait_serial: int) -> void:
	if ai_agent_analysis_delay_sec > 0.0:
		await get_tree().create_timer(ai_agent_analysis_delay_sec).timeout
	var uses_wait_gate := wait_serial >= 0
	if uses_wait_gate and (!_waiting_for_ai_agent_reply or wait_serial != _ai_agent_wait_serial):
		return
	if !_in_match or board == null or board.state == null:
		if uses_wait_gate:
			_finish_ai_agent_reply_wait()
		return
	if expected_move_count >= 0 and board.state.move_history.size() != expected_move_count:
		if uses_wait_gate:
			_finish_ai_agent_reply_wait()
		return
	_ai_agent_analysis_queued = false
	var wait_for_reply: bool = await _notify_ai_about_move(move)
	if uses_wait_gate and !wait_for_reply:
		_finish_ai_agent_reply_wait()

func _should_gate_ai_agent_before_pikafish() -> bool:
	if !wait_for_ai_agent_before_pikafish:
		return false
	if !ai_enabled or !_is_ai_turn():
		return false
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return false
	if !chess_ai_wrapper.has_api_key():
		return false
	return true

func _notify_ai_about_move(move: XiangqiMove) -> bool:
	if move == null or _applying_ai_move:
		return false
	if _game_end_review_requested:
		return false
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return false
	if !chess_ai_wrapper.has_api_key():
		return false
	if board == null or board.state == null:
		return false

	var after_state: XiangqiState = board.state.duplicate()
	var before_state: XiangqiState = after_state.duplicate()
	var undone_move := before_state.undo_move()
	if undone_move == null or !undone_move.is_valid():
		return false

	var engine_analysis: Dictionary = await _analyze_player_move_for_ai_agent(before_state, after_state, move)
	if !_in_match or chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return false
	var session: Dictionary = chess_ai_wrapper.create_game_session(after_state, human_side, ai_enabled, _notation_initial_state)
	var move_number := int((after_state.move_history.size() - 1) / 2) + 1
	var move_record: Dictionary = chess_ai_wrapper.create_move_record(
		move,
		int(engine_analysis.get("evaluation_score", 0)),
		String(engine_analysis.get("best_move", "")),
		move_number
	)
	move_record["PlyIndex"] = after_state.move_history.size()
	move_record["PikafishAnalysis"] = engine_analysis.duplicate(true)
	move_record["ChineseNotation"] = XiangqiNotation.move_to_chinese(before_state, move)
	if session.has("MoveHistory") and session["MoveHistory"] is Array:
		var move_history: Array = session["MoveHistory"]
		if !move_history.is_empty():
			move_history[move_history.size() - 1] = move_record

	var should_wait_for_reply: bool = _should_wait_for_ai_agent_reply()
	var request_sent := chess_ai_wrapper.send_move_played(move_record, session)
	return request_sent and should_wait_for_reply

func _queue_ai_agent_banter_after_undo(undone_count: int, undone_move_text: String) -> void:
	if undone_count <= 0:
		return
	if chess_ai_wrapper == null:
		_initialize_chess_ai()
	if chess_ai_wrapper == null or !chess_ai_wrapper.is_available():
		return
	if !chess_ai_wrapper.has_api_key():
		return
	if board == null or board.state == null:
		return
	var session: Dictionary = chess_ai_wrapper.create_game_session(board.state, human_side, ai_enabled, _notation_initial_state)
	session["LastAction"] = "undo"
	session["UndoneCount"] = undone_count
	session["UndoneMovesText"] = undone_move_text
	chess_ai_wrapper.send_undo_performed(session, undone_count, undone_move_text)

func _should_wait_for_ai_agent_reply() -> bool:
	if !wait_for_ai_agent_before_pikafish:
		return false
	if !ai_enabled or !_is_ai_turn():
		return false
	return true

func _begin_ai_agent_reply_wait() -> void:
	if _waiting_for_ai_agent_reply:
		return
	_waiting_for_ai_agent_reply = true
	_ai_agent_analysis_queued = false
	_ai_agent_wait_serial += 1
	_ai_agent_wait_move_count = board.state.move_history.size() if board != null and board.state != null else -1
	phase = MatchPhase.AI_THINKING
	if board != null:
		board.clear_selection()
	_sync_board_interaction()
	_refresh_match_ui(tr("XQ_AI_AGENT_REPLYING"))
	if ai_agent_wait_timeout_sec > 0.0:
		call_deferred("_release_ai_agent_wait_after_timeout", _ai_agent_wait_serial)

func _release_ai_agent_wait_after_timeout(wait_serial: int) -> void:
	await get_tree().create_timer(ai_agent_wait_timeout_sec).timeout
	if !_waiting_for_ai_agent_reply or wait_serial != _ai_agent_wait_serial:
		return
	_finish_ai_agent_reply_wait()

func _finish_ai_agent_reply_wait() -> void:
	if !_waiting_for_ai_agent_reply:
		return
	_waiting_for_ai_agent_reply = false
	_ai_agent_analysis_queued = false
	_ai_agent_wait_serial += 1
	var expected_move_count := _ai_agent_wait_move_count
	_ai_agent_wait_move_count = -1
	if board == null or board.state == null:
		_advance_turn_flow()
		_flush_pending_ai_review()
		return
	if expected_move_count >= 0 and board.state.move_history.size() != expected_move_count:
		_advance_turn_flow()
		_flush_pending_ai_review()
		return
	var status := XiangqiRules.get_position_status(board.state)
	if status == "checkmate" or status == "stalemate":
		_advance_turn_flow()
		_refresh_match_ui()
		_flush_pending_ai_review()
		return
	if !ai_enabled or !_is_ai_turn():
		_advance_turn_flow()
		_refresh_match_ui()
		_flush_pending_ai_review()
		return
	last_feedback = tr("XQ_AI_REPLY_DONE")
	phase = MatchPhase.PLAYER_TURN
	_begin_ai_turn(true)
	_flush_pending_ai_review()

func _cancel_ai_agent_reply_wait() -> void:
	if !_waiting_for_ai_agent_reply:
		return
	_waiting_for_ai_agent_reply = false
	_ai_agent_analysis_queued = false
	_ai_agent_wait_serial += 1
	_ai_agent_wait_move_count = -1

func _on_chess_ai_response(response_type: String, content: String) -> void:
	var clean_type := response_type.strip_edges()
	var lower_type := clean_type.to_lower()
	var clean_content := _clean_ai_io_visible_text(content)
	if lower_type == "none":
		if _waiting_for_ai_agent_reply:
			_finish_ai_agent_reply_wait()
		return
	if !(lower_type in ["chat", "banter", "review", "error"]):
		return
	if clean_content.is_empty() or _is_internal_ai_io_text(clean_content):
		if _waiting_for_ai_agent_reply and lower_type in ["banter", "error"]:
			_finish_ai_agent_reply_wait()
		return
	if lower_type == "chat" or (_ai_chat_waiting and lower_type == "error"):
		_ai_chat_waiting = false
		_set_ai_io_chat_response("chat_error" if lower_type == "error" else "chat_ai", clean_content)
		if _waiting_for_ai_agent_reply and lower_type == "error":
			_finish_ai_agent_reply_wait()
		return
	if _ai_chat_waiting and lower_type in ["review", "banter"]:
		_ai_chat_waiting = false
		_set_ai_io_chat_response("chat_ai", _format_ai_response_display_text(clean_type, clean_content))
		return
	if _ai_review_waiting and lower_type == "error":
		_ai_review_waiting = false
		_game_end_review_requested = false
		_game_end_review_generated = false
		last_feedback = tr("XQ_REVIEW_FAILED")
		if _waiting_for_ai_agent_reply:
			_pending_review_content = "[%s]\n%s" % [clean_type, clean_content]
			_pending_review_data = ""
			_finish_ai_agent_reply_wait()
		else:
			_set_ai_io_response("error", "[%s]\n%s" % [clean_type, clean_content])
		_refresh_match_ui()
		return
	var display_text := _format_ai_response_display_text(clean_type, clean_content)
	var role := "error" if lower_type == "error" else ("review" if lower_type == "review" else "ai_agent")
	_set_ai_io_response(role, display_text)
	if _waiting_for_ai_agent_reply and lower_type in ["banter", "error"]:
		_finish_ai_agent_reply_wait()

func _on_chess_ai_review_generated(review_content: String, _review_data: String) -> void:
	var clean_content := review_content.strip_edges()
	if clean_content.is_empty():
		return
	if !_game_end_review_requested and !_ai_review_waiting:
		return
	_ai_review_waiting = false
	_game_end_review_generated = true
	if _game_end_result.is_empty() and board != null and board.state != null:
		_game_end_status = XiangqiRules.get_position_status(board.state)
		_game_end_result = _game_result_text(_game_end_status)
	if _waiting_for_ai_agent_reply:
		_pending_review_content = _format_ai_response_display_text("review", clean_content)
		_pending_review_data = _review_data
		return
	last_feedback = tr("MATCH_REVIEW_GENERATED")
	_set_ai_io_response("review", _format_ai_response_display_text("review", clean_content))
	_refresh_match_ui()

func _flush_pending_ai_review() -> void:
	var clean_content := _pending_review_content.strip_edges()
	if clean_content.is_empty():
		return
	var role := "error" if clean_content.begins_with("[error]") else "review"
	_pending_review_content = ""
	_pending_review_data = ""
	if role == "review":
		_game_end_review_generated = true
	_set_ai_io_response(role, clean_content)

func _format_move_for_io(move: XiangqiMove) -> String:
	if move == null:
		return ""
	var coordinate := move.to_coordinate_string()
	var state_before_move := _state_before_last_move()
	var notation := XiangqiNotation.move_to_chinese(state_before_move, move)
	var move_text := coordinate if notation.is_empty() else "%s (%s)" % [notation, coordinate]
	if move.captured_piece.is_empty():
		return move_text
	return "%s，吃掉%s" % [move_text, _piece_prompt_name(move.captured_piece)]

func _piece_prompt_name(piece: String) -> String:
	match piece:
		"K":
			return "红帅"
		"A":
			return "红仕"
		"E":
			return "红相"
		"H":
			return "红马"
		"R":
			return "红车"
		"C":
			return "红炮"
		"P":
			return "红兵"
		"k":
			return "黑将"
		"a":
			return "黑士"
		"e":
			return "黑象"
		"h":
			return "黑马"
		"r":
			return "黑车"
		"c":
			return "黑炮"
		"p":
			return "黑卒"
		_:
			return piece

func _state_before_last_move() -> XiangqiState:
	if _notation_initial_state == null or board == null or board.state == null:
		return null
	var replay_state := _notation_initial_state.duplicate()
	var history_size := board.state.move_history.size()
	for index: int in range(maxi(0, history_size - 1)):
		var replay_move := board.state.move_history[index] as XiangqiMove
		if replay_move != null:
			replay_state.apply_move(replay_move)
	return replay_state

func _effective_ai_movetime_ms() -> int:
	return maxi(1, relax_ai_movetime_ms if xiangqi_ai_relax else ai_movetime_ms)

func _effective_ai_search_depth() -> int:
	if xiangqi_ai_relax:
		return maxi(1, relax_ai_search_depth)
	return maxi(0, ai_search_depth)

func _effective_ai_skill_level() -> int:
	return clampi(relax_ai_skill_level if xiangqi_ai_relax else ai_skill_level, 0, 20)

func _request_ai_bestmove_threaded(state: XiangqiState, movetime_ms: int, depth: int, skill_level: int) -> Dictionary:
	if state == null:
		return {
			"ok": false,
			"error": "Cannot search a null XiangqiState.",
		}
	var result: Dictionary = await _run_pikafish_worker(
		&"run_bestmove",
		[state.duplicate(), movetime_ms, depth, skill_level]
	)
	return result

func _run_pikafish_worker(method_name: StringName, args: Array) -> Dictionary:
	var worker: RefCounted = PikafishThreadWorkerScript.new()
	var mutex := Mutex.new()
	var shared: Dictionary = {
		"done": false,
		"result": {},
	}
	var task: Callable = func() -> void:
		var call_result: Variant = worker.callv(method_name, args)
		var worker_result: Dictionary = {}
		if call_result is Dictionary:
			worker_result = (call_result as Dictionary).duplicate()
		else:
			worker_result = {
				"ok": false,
				"error": "Pikafish worker finished without a Dictionary result.",
			}
		mutex.lock()
		shared["result"] = worker_result
		shared["done"] = true
		mutex.unlock()

	var thread := Thread.new()
	var start_error: int = thread.start(task)
	if start_error != OK:
		return {
			"ok": false,
			"error": "Failed to start Pikafish thread (%d)." % start_error,
		}
	_active_pikafish_threads.push_back(thread)

	while true:
		mutex.lock()
		var done: bool = bool(shared.get("done", false))
		mutex.unlock()
		if done:
			break
		if !is_inside_tree():
			break
		await get_tree().process_frame

	if _joined_pikafish_threads.has(thread):
		_joined_pikafish_threads.erase(thread)
	else:
		thread.wait_to_finish()
	_active_pikafish_threads.erase(thread)
	mutex.lock()
	var result_variant: Variant = shared.get("result", {})
	var final_result: Dictionary = {}
	if result_variant is Dictionary:
		final_result = (result_variant as Dictionary).duplicate()
	mutex.unlock()
	if final_result.is_empty():
		return {
			"ok": false,
			"error": "Pikafish thread finished without a result.",
		}
	return final_result

func _wait_for_active_pikafish_threads() -> void:
	var threads: Array = _active_pikafish_threads.duplicate()
	_active_pikafish_threads.clear()
	for thread_variant in threads:
		var thread := thread_variant as Thread
		if thread == null:
			continue
		thread.wait_to_finish()
		_joined_pikafish_threads.push_back(thread)

func _analyze_player_move_for_ai_agent(before_state: XiangqiState, after_state: XiangqiState, played_move: XiangqiMove) -> Dictionary:
	var result: Dictionary = {
		"evaluation_score": 0,
		"best_move": "",
		"played_move": "",
		"is_engine_best_move": false,
		"before": {},
		"after": {},
	}
	if before_state == null or after_state == null or played_move == null or !played_move.is_valid():
		return result

	var threaded_result: Dictionary = await _run_pikafish_worker(
		&"run_player_move_analysis",
		[
			before_state.duplicate(),
			after_state.duplicate(),
			played_move.duplicate(),
			ai_agent_analysis_movetime_ms,
			ai_agent_analysis_depth,
		]
	)
	if !bool(threaded_result.get("ok", false)):
		return result

	result = threaded_result.duplicate(true)
	result["evaluation_score"] = int(result.get("evaluation_score", 0))
	result["best_move"] = String(result.get("best_move", ""))
	return result

func _analysis_best_move_text(analysis: Dictionary) -> String:
	var best_move := analysis.get("bestmove") as XiangqiMove
	if best_move != null and best_move.is_valid():
		return best_move.to_coordinate_string()
	return String(analysis.get("bestmove_text", ""))

func _format_best_move_for_ai_agent(analysis: Dictionary, state: XiangqiState) -> String:
	var best_move := analysis.get("bestmove") as XiangqiMove
	if best_move == null or !best_move.is_valid():
		return String(analysis.get("bestmove_text", ""))
	var coordinate := best_move.to_coordinate_string()
	var notation := XiangqiNotation.move_to_chinese(state, best_move)
	if notation.is_empty():
		return coordinate
	return "%s (%s)" % [notation, coordinate]

func _capture_match_view_setup() -> void:
	if board == null:
		return
	if board.get_anchor_count() == 0:
		board.refresh_anchor_nodes()
	_board_idle_transform = board.transform
	_board_local_focus_point = _get_board_local_focus_point()
	_board_flipped_transform = _build_flipped_board_transform(_board_idle_transform)
	_board_reference_side = _resolve_board_reference_side()
	_board_camera_transform = board_camera.transform
	_board_camera_fov = board_camera.fov
	_match_view_ready = true

func _apply_board_transform_for_side(side: int) -> void:
	if board == null:
		return
	if !_match_view_ready:
		_capture_match_view_setup()
	board.transform = _board_idle_transform if side == _board_reference_side else _board_flipped_transform

func _restore_idle_board_transform() -> void:
	if board == null:
		return
	if !_match_view_ready:
		_capture_match_view_setup()
	board.transform = _board_idle_transform

func _restore_idle_board_camera() -> void:
	if board_camera == null:
		return
	if !_match_view_ready:
		_capture_match_view_setup()
	board_camera.transform = _board_camera_transform
	board_camera.fov = _board_camera_fov

func _move_player_camera(target_camera: Camera3D, instant: bool = false) -> void:
	if target_camera == null or player == null:
		return
	var active_camera := _get_active_scene_camera()
	if active_camera != null and _camera_is_near(active_camera, target_camera):
		return
	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null

	if instant:
		player.force_set_camera(target_camera)
		return

	var player_head := player.get_node_or_null("head") as Node3D
	if player_head == null or active_camera == null:
		player.move_camera(target_camera)
		return

	_camera_tween = create_tween()
	_camera_tween.tween_property(player_head, "global_transform", target_camera.global_transform, CAMERA_TRANSITION_SECONDS).set_trans(Tween.TRANS_SINE)
	_camera_tween.set_parallel(true)
	_camera_tween.tween_property(active_camera, "fov", target_camera.fov, CAMERA_TRANSITION_SECONDS).set_trans(Tween.TRANS_SINE)
	_camera_tween.set_parallel(false)

func _camera_is_near(actual: Camera3D, expected: Camera3D) -> bool:
	if actual == null or expected == null:
		return false
	return \
		actual.global_position.distance_to(expected.global_position) < 0.001 and \
		absf(actual.fov - expected.fov) < 0.01

func _enter_notation_view() -> void:
	if !_in_match or _is_paper_view_active():
		return
	_notation_view_active = true
	_ai_io_view_active = false
	board.clear_selection()
	_sync_board_interaction()
	_move_player_camera(paper_camera)
	_refresh_match_ui()

func _exit_notation_view() -> void:
	_exit_paper_view()

func _enter_ai_io_view() -> void:
	if !_in_match or _is_paper_view_active():
		return
	_notation_view_active = false
	_ai_io_view_active = true
	board.clear_selection()
	_sync_board_interaction()
	_move_player_camera(ai_io_camera)
	_refresh_match_ui()

func _exit_paper_view() -> void:
	if !_is_paper_view_active():
		return
	_notation_view_active = false
	_ai_io_view_active = false
	_move_player_camera(board_camera)
	_sync_board_interaction()
	_refresh_match_ui()

func _is_paper_view_active() -> bool:
	return _notation_view_active or _ai_io_view_active

func _get_active_scene_camera() -> Camera3D:
	if player != null and player.has_method("get_camera"):
		var active_camera = player.get_camera() as Camera3D
		if active_camera != null:
			return active_camera
	return board_camera

func _build_flipped_board_transform(base_transform: Transform3D) -> Transform3D:
	var to_focus := Transform3D(Basis.IDENTITY, _board_local_focus_point)
	var from_focus := Transform3D(Basis.IDENTITY, -_board_local_focus_point)
	var flip_rotation := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	return base_transform * to_focus * flip_rotation * from_focus

func _resolve_board_reference_side() -> int:
	if board == null or board_camera == null:
		return XiangqiConstants.RED
	var focus_point := board.to_global(_board_local_focus_point)
	var camera_offset := board_camera.global_position - focus_point
	return XiangqiConstants.RED if camera_offset.dot(_get_board_global_rank_axis()) >= 0.0 else XiangqiConstants.BLACK

func _get_board_local_focus_point() -> Vector3:
	if board == null:
		return Vector3.ZERO
	if board.get_anchor_count() == 0:
		board.refresh_anchor_nodes()
	return (_get_board_rank_center_local(0) + _get_board_rank_center_local(XiangqiConstants.BOARD_RANKS - 1)) * 0.5

func _get_board_global_rank_axis() -> Vector3:
	if board == null:
		return Vector3.FORWARD
	var local_rank_axis := _get_board_rank_axis_local()
	if local_rank_axis.length_squared() <= 0.000001:
		return -board.global_transform.basis.z.normalized()
	return (board.global_transform.basis * local_rank_axis).normalized()

func _get_board_rank_axis_local() -> Vector3:
	if board == null:
		return Vector3.FORWARD
	var rank_axis := _get_board_rank_center_local(XiangqiConstants.BOARD_RANKS - 1) - _get_board_rank_center_local(0)
	if rank_axis.length_squared() <= 0.000001:
		return -Vector3.FORWARD
	return rank_axis.normalized()

func _get_board_rank_center_local(rank: int) -> Vector3:
	if board == null:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var count := 0
	for file: int in XiangqiConstants.BOARD_FILES:
		var anchor := board.get_anchor_node(XiangqiCoord.to_name(file, rank))
		if anchor == null:
			continue
		sum += anchor.global_position
		count += 1
	if count == 0:
		return Vector3.ZERO
	return board.to_local(sum / float(count))

func _top_prompt_text() -> String:
	if board == null or board.state == null:
		return tr("XQ_TITLE")
	var status := XiangqiRules.get_position_status(board.state)
	if phase == MatchPhase.GAME_OVER:
		if status == "checkmate" or status == "stalemate":
			return tr("XQ_CHECKMATE")
		return tr("XQ_GAME_OVER")
	if phase == MatchPhase.AI_THINKING:
		return tr("XQ_AI_TURN")
	if _is_human_turn():
		return tr("XQ_YOUR_TURN")
	return tr("XQ_SIDE_TURN") % _side_text(board.state.side_to_move)

func _side_text(side: int) -> String:
	return tr("SIDE_RED") if side == XiangqiConstants.RED else tr("SIDE_BLACK")
