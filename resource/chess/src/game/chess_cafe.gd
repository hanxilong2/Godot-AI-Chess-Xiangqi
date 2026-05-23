extends Level

signal standard_game_finished()
signal standard_api_key_screen_closed()

const STANDARD_CAMERA_TRANSITION_SECONDS:float = 0.5
const STANDARD_CLOCK_FOCUS_COLLISION_MASK:int = 4
const STANDARD_CLOCK_INITIAL_TIME:float = 15.0 * 60.0
const STANDARD_CLOCK_INCREMENT_TIME:float = 5.0
const STANDARD_CLOCK_TICK_STREAM_PATH:String = "res://assets/audio/chess_clock_tick.mp3"
const STANDARD_CHESS_INITIAL_FEN:String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
const STANDARD_DEBUG_ENGINE_STATS:bool = false
const RADIO_MUSIC_DIRECTORY:String = "res://assets/audio"
const RADIO_MUSIC_IMPORT_SUFFIX:String = ".mp3.import"
const RADIO_MUSIC_EXCLUDED_FILES:Array = [
	"719560__dartekz_gamez__wind-whirl-small-air-blow.mp3",
	"chess_clock_tick.mp3",
]
const RADIO_MUSIC_OPTION_PREVIOUS:String = "RADIO_MUSIC_OPTION_PREVIOUS"
const RADIO_MUSIC_OPTION_NEXT:String = "RADIO_MUSIC_OPTION_NEXT"
const RADIO_MUSIC_OPTION_VOLUME_HIGH:String = "RADIO_MUSIC_OPTION_VOLUME_HIGH"
const RADIO_MUSIC_OPTION_VOLUME_MEDIUM:String = "RADIO_MUSIC_OPTION_VOLUME_MEDIUM"
const RADIO_MUSIC_OPTION_VOLUME_LOW:String = "RADIO_MUSIC_OPTION_VOLUME_LOW"
const RADIO_MUSIC_OPTION_PLAY:String = "RADIO_MUSIC_OPTION_PLAY"
const RADIO_MUSIC_OPTION_STOP:String = "RADIO_MUSIC_OPTION_STOP"
const RADIO_MUSIC_OPTION_EXIT:String = "RADIO_MUSIC_OPTION_EXIT"
const RADIO_MUSIC_VOLUME_HIGH:String = "high"
const RADIO_MUSIC_VOLUME_MEDIUM:String = "medium"
const RADIO_MUSIC_VOLUME_LOW:String = "low"
const OPTION_CHESS_DIFFICULTY_STANDARD:String = "SELECTION_DIFFICULTY_STANDARD"
const OPTION_CHESS_DIFFICULTY_RELAX:String = "SELECTION_DIFFICULTY_RELAX"
const OPTION_CANCEL:String = "SELECTION_CANCEL"

var standard_history_zobrist:PackedInt64Array = []
var standard_history_state:Array[State] = []
var standard_history_event:Array[Dictionary] = []
var standard_history_move:PackedInt32Array = []
@onready var standard_history_document:Document = load("res://scene/doc/history.tscn").instantiate()
var standard_engine:ChessEngine = PastorEngine.new()
var standard_state_machine:StateMachine = StateMachine.new()
var chessboard_state:String = ""
var standard_player_group:int = 0
var standard_initial_state:State = null
var standard_clock_remaining:Array[float] = [STANDARD_CLOCK_INITIAL_TIME, STANDARD_CLOCK_INITIAL_TIME]
var standard_clock_active_group:int = -1
var standard_clock_running:bool = false
var standard_match_active:bool = false
var standard_game_over:bool = false
var standard_relax_ai:bool = false
var standard_review_end_type:String = ""
var standard_review_result:String = ""
var standard_ai_review_waiting:bool = false
var standard_game_end_review_requested:bool = false
var standard_chess_ai_wrapper:ChessAIWrapper = null
var standard_ai_io_view_active:bool = false
var standard_ai_io_entries:Array = []
var standard_clock_view_active:bool = false
var standard_camera_tween:Tween = null
var standard_clock_tick_player:AudioStreamPlayer = null
var standard_undo_in_progress:bool = false
var standard_extra_move_bottom_bar_was_visible:bool = false
var radio_music_player:AudioStreamPlayer = null
var radio_music_playlist:PackedStringArray = []
var radio_music_track_names:PackedStringArray = []
var radio_music_track_index:int = 0
var radio_music_volume_level:String = RADIO_MUSIC_VOLUME_MEDIUM
@onready var standard_clock_view_camera:Camera3D = $camera_clock
@onready var standard_ai_io_camera:Camera3D = $camera_ai_io_paper
@onready var standard_ai_io_paper:Node = $table_0/xiangqi_ai_io_paper
@onready var standard_clock_focus_area:Area3D = $table_0/chess_clock/clock_focus_area
@onready var standard_clock_player_label:Label3D = $table_0/chess_clock/player_time
@onready var standard_clock_opponent_label:Label3D = $table_0/chess_clock/opponent_time
@onready var standard_review_top_bar:ColorRect = $ui_overlay/top_bar
@onready var standard_review_top_label:Label = $ui_overlay/top_bar/top_label
@onready var standard_review_bottom_bar:ColorRect = $ui_overlay/bottom_bar
@onready var standard_review_status_label:Label = $ui_overlay/bottom_bar/review_status_label
@onready var standard_undo_button:Button = $ui_overlay/bottom_bar/undo_button
@onready var standard_leave_button:Button = $ui_overlay/bottom_bar/leave_button
@onready var standard_api_key_button:Button = $ui_overlay/bottom_bar/api_key_button
@onready var standard_review_button:Button = get_node_or_null("ui_overlay/bottom_bar/review_button") as Button
@onready var standard_review_panel:ColorRect = $ui_overlay/review_panel
@onready var standard_review_text:RichTextLabel = $ui_overlay/review_panel/panel/review_text
@onready var standard_review_close_button:Button = $ui_overlay/review_panel/panel/close_button
@onready var standard_api_key_screen:Control = $ui_overlay/api_key_screen
@onready var standard_api_key_input:LineEdit = $ui_overlay/api_key_screen/panel/api_key_input
@onready var standard_api_key_status_label:Label = $ui_overlay/api_key_screen/panel/status_label
@onready var standard_api_key_save_button:Button = $ui_overlay/api_key_screen/panel/save_button
@onready var standard_api_key_clear_button:Button = $ui_overlay/api_key_screen/panel/clear_button
@onready var standard_api_key_back_button:Button = $ui_overlay/api_key_screen/panel/back_button

func _exit_tree() -> void:
	standard_cleanup_runtime_audio()
	if standard_engine != null:
		standard_engine.stop_search()
		standard_engine = null
	if is_instance_valid(standard_history_document):
		standard_history_document.free()
		standard_history_document = null
	standard_history_zobrist.clear()
	standard_history_state.clear()
	standard_history_event.clear()
	standard_history_move.clear()
	standard_state_machine = null
	standard_clock_running = false
	standard_match_active = false
	standard_game_over = false
	standard_undo_in_progress = false
	standard_chess_ai_wrapper = null
	if standard_camera_tween != null:
		standard_camera_tween.kill()
		standard_camera_tween = null
	super._exit_tree()

func standard_cleanup_runtime_audio() -> void:
	standard_clock_running = false
	standard_clock_cleanup_audio_players()
	radio_music_cleanup_audio_player()
	if is_instance_valid(Ambient):
		Ambient.clear_environment_sound()

func _ready() -> void:
	super._ready()
	if !tree_exiting.is_connected(standard_cleanup_runtime_audio):
		tree_exiting.connect(standard_cleanup_runtime_audio, CONNECT_ONE_SHOT)
	if !get_tree().root.tree_exiting.is_connected(standard_cleanup_runtime_audio):
		get_tree().root.tree_exiting.connect(standard_cleanup_runtime_audio, CONNECT_ONE_SHOT)
	standard_clock_reset()
	add_child(standard_state_machine)
	standard_state_machine.name = "standard"
	standard_history_document.set_filename("history.match_with_yulan.json")
	standard_history_document.load_file()
	Ambient.change_environment_sound(load("res://assets/audio/52645__kstein1__white-noise.wav"))
	var cheshire_by:int = get_meta("by")
	var cheshire_instance:Actor = load("res://scene/actor/cheshire.tscn").instantiate()
	cheshire_instance.position = $chessboard.x88_to_vector3(cheshire_by)
	$chessboard.state.add_piece(cheshire_by, player_king)
	$chessboard.add_piece_instance(cheshire_instance, cheshire_by)
	chessboard.button_input_pointer = cheshire_by

	standard_engine.set_think_time(INF)
	$table_0/chessboard_standard.set_enabled(false)
	$player.add_inspectable_item($table_0/chessboard_standard)
	$pastor.play_animation("thinking")
	title[0x54] = "CHAR_YULAN"
	title[0x55] = "CHAR_YULAN"
	title[0x41] = "RADIO_MUSIC_TITLE"
	radio_music_ensure_audio_player()
	standard_state_machine.add_state("start", state_ready_in_game_start)
	standard_state_machine.add_state("opponent", state_ready_in_game_opponent)
	standard_state_machine.add_state("waiting", state_ready_in_game_waiting)
	standard_state_machine.add_state("move", state_ready_in_game_move)
	standard_state_machine.add_state("player", state_ready_in_game_player, state_exit_in_game_player)
	standard_state_machine.add_state("ready_to_move", state_ready_in_game_ready_to_move)
	standard_state_machine.add_state("check_move", state_ready_in_game_check_move)
	standard_state_machine.add_state("extra_move", state_ready_in_game_extra_move, state_exit_in_game_extra_move)
	standard_state_machine.add_state("game_end", state_ready_game_end)
	standard_initialize_chess_ai()
	standard_initialize_review_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE || what == NOTIFICATION_WM_CLOSE_REQUEST:
		standard_cleanup_runtime_audio()
		return
	if what != NOTIFICATION_TRANSLATION_CHANGED or !is_node_ready():
		return
	standard_refresh_review_tools()
	standard_refresh_api_key_status()
	if standard_api_key_input != null:
		standard_api_key_input.placeholder_text = tr("API_KEY_PLACEHOLDER")
	if standard_ai_io_paper != null:
		if standard_ai_io_paper.has_method("set_title_text"):
			standard_ai_io_paper.set_title_text("MATCH_REVIEW_TITLE")
		if standard_ai_io_paper.has_method("set_entries"):
			standard_ai_io_paper.set_entries(standard_ai_io_entries)

func standard_clock_ensure_audio_players() -> void:
	if standard_clock_tick_player == null:
		standard_clock_tick_player = AudioStreamPlayer.new()
		standard_clock_tick_player.name = "standard_clock_tick_player"
		standard_clock_tick_player.bus = &"SFX"
		standard_clock_tick_player.volume_db = -8.0
		var tick_stream:AudioStream = load(STANDARD_CLOCK_TICK_STREAM_PATH)
		if tick_stream != null:
			tick_stream = tick_stream.duplicate() as AudioStream
			var tick_mp3 := tick_stream as AudioStreamMP3
			if tick_mp3 != null:
				tick_mp3.loop = true
			standard_clock_tick_player.stream = tick_stream
		add_child(standard_clock_tick_player)
		standard_clock_tick_player.finished.connect(standard_clock_restart_tick)

func standard_clock_cleanup_audio_players() -> void:
	if is_instance_valid(standard_clock_tick_player):
		if standard_clock_tick_player.finished.is_connected(standard_clock_restart_tick):
			standard_clock_tick_player.finished.disconnect(standard_clock_restart_tick)
		standard_clock_tick_player.stop()
		standard_clock_tick_player.stream = null
		if standard_clock_tick_player.get_parent() != null:
			standard_clock_tick_player.get_parent().remove_child(standard_clock_tick_player)
		standard_clock_tick_player.free()
	standard_clock_tick_player = null

func standard_clock_start_tick() -> void:
	standard_clock_ensure_audio_players()
	if standard_clock_tick_player == null || standard_clock_tick_player.stream == null:
		return
	if !standard_clock_tick_player.playing:
		standard_clock_tick_player.play()

func standard_clock_stop_tick() -> void:
	if standard_clock_tick_player != null:
		standard_clock_tick_player.stop()

func standard_clock_restart_tick() -> void:
	if standard_match_active:
		standard_clock_start_tick()

func radio_music_ensure_audio_player() -> void:
	radio_music_load_playlist()
	if radio_music_player == null:
		radio_music_player = AudioStreamPlayer.new()
		radio_music_player.name = "radio_music_player"
		radio_music_player.bus = &"Ambient"
		add_child(radio_music_player)
		radio_music_player.finished.connect(radio_music_on_finished)
	radio_music_apply_volume()
	if radio_music_player.stream == null && !radio_music_playlist.is_empty():
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
	var dir:DirAccess = DirAccess.open(RADIO_MUSIC_DIRECTORY)
	if dir == null:
		return
	var files:PackedStringArray = []
	dir.list_dir_begin()
	while true:
		var file_name:String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		var music_file_name:String = radio_music_normalize_file_name(file_name)
		if music_file_name.is_empty():
			continue
		if RADIO_MUSIC_EXCLUDED_FILES.has(music_file_name):
			continue
		if files.has(music_file_name):
			continue
		files.push_back(music_file_name)
	dir.list_dir_end()
	files.sort()
	for file_name:String in files:
		radio_music_playlist.push_back("%s/%s" % [RADIO_MUSIC_DIRECTORY, file_name])
		radio_music_track_names.push_back(file_name.get_basename())

func radio_music_normalize_file_name(file_name:String) -> String:
	if file_name.get_extension().to_lower() == "mp3":
		return file_name
	if file_name.to_lower().ends_with(RADIO_MUSIC_IMPORT_SUFFIX):
		return file_name.substr(0, file_name.length() - ".import".length())
	return ""

func radio_music_play_track(track_index:int) -> void:
	if radio_music_player == null:
		radio_music_ensure_audio_player()
	if radio_music_player == null || radio_music_playlist.is_empty():
		return
	radio_music_track_index = posmod(track_index, radio_music_playlist.size())
	var stream:AudioStream = radio_music_load_stream(radio_music_playlist[radio_music_track_index])
	if stream == null:
		radio_music_player.stream = null
		return
	radio_music_player.stream = stream
	radio_music_apply_volume()
	radio_music_player.play()

func radio_music_load_stream(path:String) -> AudioStream:
	var stream:AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null:
		stream = radio_music_load_mp3_from_file(path)
	if stream == null:
		return null
	var duplicate_stream:AudioStream = stream.duplicate() as AudioStream
	if duplicate_stream != null:
		stream = duplicate_stream
	var mp3_stream := stream as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = false
	return stream

func radio_music_load_mp3_from_file(path:String) -> AudioStream:
	if path.get_extension().to_lower() != "mp3":
		return null
	if !FileAccess.file_exists(path):
		return null
	var file:FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var stream := AudioStreamMP3.new()
	stream.data = file.get_buffer(int(file.get_length()))
	stream.loop = false
	return stream

func radio_music_on_finished() -> void:
	radio_music_step(1)

func radio_music_step(delta:int) -> void:
	if radio_music_playlist.is_empty():
		return
	radio_music_play_track(radio_music_track_index + delta)

func radio_music_set_volume(level:String) -> void:
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
	return radio_music_player != null && radio_music_player.playing

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

func _process(delta:float) -> void:
	if !standard_clock_running:
		return
	if standard_clock_active_group < 0 || standard_clock_active_group >= standard_clock_remaining.size():
		return
	standard_clock_remaining[standard_clock_active_group] = maxf(0.0, standard_clock_remaining[standard_clock_active_group] - delta)
	if standard_clock_remaining[standard_clock_active_group] <= 0.0:
		standard_handle_clock_timeout(standard_clock_active_group)
		return
	standard_clock_update_labels()

func standard_handle_clock_timeout(loser_group:int) -> void:
	if standard_game_over || !standard_match_active:
		return
	if loser_group != 0 && loser_group != 1:
		return
	standard_clock_remaining[loser_group] = 0.0
	standard_clock_running = false
	standard_clock_stop_tick()
	standard_clock_update_labels()
	var timeout_end_type:String = "timeout_white" if loser_group == 0 else "timeout_black"
	standard_state_machine.change_state("game_end", {"end_type": timeout_end_type})

func _input(event:InputEvent) -> void:
	if standard_is_api_key_screen_visible() || standard_review_panel.visible:
		return
	if !standard_match_active:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null || !mouse_event.pressed:
		return
	if standard_handle_focus_mouse_input(mouse_event):
		get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent) -> void:
	if standard_is_api_key_screen_visible():
		var overlay_key_event := event as InputEventKey
		if overlay_key_event != null && overlay_key_event.pressed && !overlay_key_event.echo && overlay_key_event.keycode == KEY_ESCAPE:
			standard_hide_api_key_screen()
			get_viewport().set_input_as_handled()
		return
	if standard_review_panel.visible:
		var panel_key_event := event as InputEventKey
		if panel_key_event != null && panel_key_event.pressed && !panel_key_event.echo && panel_key_event.keycode == KEY_ESCAPE:
			standard_review_panel.visible = false
			get_viewport().set_input_as_handled()
		return
	if standard_ai_io_view_active:
		if standard_handle_ai_io_view_input(event):
			get_viewport().set_input_as_handled()
		return
	if standard_game_over:
		if standard_handle_game_over_input(event):
			get_viewport().set_input_as_handled()
		return
	if !standard_match_active && standard_review_bottom_bar.visible:
		var review_mouse_event := event as InputEventMouseButton
		if review_mouse_event != null && review_mouse_event.pressed && review_mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if standard_ai_io_paper != null && standard_ai_io_paper.contains_screen_point(_get_standard_active_camera(), review_mouse_event.position):
				standard_enter_ai_io_view()
				get_viewport().set_input_as_handled()
		return
	if !standard_match_active:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event != null && mouse_event.pressed:
		if standard_clock_view_active:
			if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				standard_clock_exit_view()
				get_viewport().set_input_as_handled()
			elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT && standard_clock_contains_screen_point(_get_standard_active_camera(), mouse_event.position):
			standard_clock_enter_view()
			get_viewport().set_input_as_handled()
			return

	var key_event := event as InputEventKey
	if key_event == null || !key_event.pressed || key_event.echo:
		return
	if standard_clock_view_active && key_event.keycode in [KEY_ESCAPE, KEY_Q]:
		standard_clock_exit_view()
		get_viewport().set_input_as_handled()

func standard_handle_focus_mouse_input(mouse_event:InputEventMouseButton) -> bool:
	if standard_clock_view_active:
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			standard_clock_exit_view()
			return true
		return mouse_event.button_index == MOUSE_BUTTON_LEFT

	if standard_ai_io_view_active:
		return standard_handle_ai_io_view_input(mouse_event)

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return false

	var active_camera:Camera3D = _get_standard_active_camera()
	if standard_clock_contains_screen_point(active_camera, mouse_event.position):
		standard_clock_enter_view()
		return true

	if !standard_ai_io_entries.is_empty() && standard_ai_io_paper != null && standard_ai_io_paper.contains_screen_point(active_camera, mouse_event.position):
		standard_enter_ai_io_view()
		return true

	return false

func standard_handle_game_over_input(event:InputEvent) -> bool:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null && mouse_event.pressed:
		return standard_handle_focus_mouse_input(mouse_event)

	var key_event := event as InputEventKey
	if key_event == null || !key_event.pressed || key_event.echo:
		return false
	if key_event.keycode in [KEY_ESCAPE, KEY_Q]:
		if standard_clock_view_active:
			standard_clock_exit_view()
			return true
		standard_leave_game()
		return true
	return false

func standard_clock_enter_view() -> void:
	if !standard_match_active || standard_clock_view_active:
		return
	standard_clock_view_active = true
	if $player != null:
		$player.can_move = false
	$table_0/chessboard_standard.set_enabled(false)
	standard_refresh_review_tools()
	standard_move_player_camera(standard_clock_view_camera)

func standard_clock_exit_view(instant:bool = false) -> void:
	if !standard_clock_view_active:
		return
	standard_clock_view_active = false
	if standard_match_active && !standard_game_over:
		$table_0/chessboard_standard.set_enabled(true)
	if $player != null:
		$player.can_move = standard_match_active && !standard_game_over
	standard_refresh_review_tools()
	standard_move_player_camera($camera_chessboard, instant)

func standard_enter_ai_io_view() -> void:
	if standard_ai_io_paper == null || standard_ai_io_view_active:
		return
	if standard_ai_io_entries.is_empty():
		return
	standard_ai_io_view_active = true
	if $player != null:
		$player.can_move = false
	if standard_match_active:
		$table_0/chessboard_standard.set_enabled(false)
	standard_refresh_review_tools()
	standard_move_player_camera(standard_ai_io_camera)

func standard_exit_ai_io_view() -> void:
	if !standard_ai_io_view_active:
		return
	standard_ai_io_view_active = false
	var target_camera:Camera3D = $camera_chessboard if standard_match_active else $camera
	standard_move_player_camera(target_camera)
	if standard_match_active:
		if !standard_game_over:
			$table_0/chessboard_standard.set_enabled(true)
		if $player != null:
			$player.can_move = !standard_game_over
	elif $player != null:
		$player.can_move = true
	standard_refresh_review_tools()

func standard_handle_ai_io_view_input(event:InputEvent) -> bool:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null && mouse_event.pressed:
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			standard_exit_ai_io_view()
			return true
		if mouse_event.button_index == MOUSE_BUTTON_LEFT && standard_ai_io_paper != null:
			var page_delta:int = standard_ai_io_paper.get_click_page_delta(_get_standard_active_camera(), mouse_event.position)
			if page_delta != 0:
				standard_turn_ai_io_page(page_delta)
				return true
			return standard_ai_io_paper.contains_screen_point(_get_standard_active_camera(), mouse_event.position)

	var key_event := event as InputEventKey
	if key_event == null || !key_event.pressed || key_event.echo:
		return false
	if key_event.keycode in [KEY_ESCAPE, KEY_Q]:
		standard_exit_ai_io_view()
		return true
	if key_event.keycode in [KEY_PAGEUP, KEY_BRACKETLEFT]:
		standard_turn_ai_io_page(-1)
		return true
	if key_event.keycode in [KEY_PAGEDOWN, KEY_BRACKETRIGHT]:
		standard_turn_ai_io_page(1)
		return true
	return false

func standard_turn_ai_io_page(delta:int) -> bool:
	if standard_ai_io_paper == null:
		return false
	var current_page:int = standard_ai_io_paper.get_current_page()
	var page_count:int = standard_ai_io_paper.get_page_count()
	if delta > 0 && current_page + delta >= page_count - 1:
		return false
	if !standard_ai_io_paper.can_turn_page(delta):
		return false
	return standard_ai_io_paper.turn_page(delta)

func standard_clock_contains_screen_point(camera:Camera3D, screen_position:Vector2) -> bool:
	if camera == null || standard_clock_focus_area == null:
		return false
	var ray_origin:Vector3 = camera.project_ray_origin(screen_position)
	var ray_end:Vector3 = ray_origin + camera.project_ray_normal(screen_position) * 100.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, STANDARD_CLOCK_FOCUS_COLLISION_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit:Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == standard_clock_focus_area

func standard_move_player_camera(target_camera:Camera3D, instant:bool = false) -> void:
	if target_camera == null:
		return
	if standard_camera_tween != null:
		standard_camera_tween.kill()
		standard_camera_tween = null
	if instant:
		$player.force_set_camera(target_camera)
		return
	var active_camera:Camera3D = _get_standard_active_camera()
	var player_head := $player.get_node_or_null("head") as Node3D
	if active_camera == null || player_head == null:
		$player.move_camera(target_camera)
		return
	standard_camera_tween = create_tween()
	standard_camera_tween.tween_property(player_head, "global_transform", target_camera.global_transform, STANDARD_CAMERA_TRANSITION_SECONDS).set_trans(Tween.TRANS_SINE)
	standard_camera_tween.set_parallel(true)
	standard_camera_tween.tween_property(active_camera, "fov", target_camera.fov, STANDARD_CAMERA_TRANSITION_SECONDS).set_trans(Tween.TRANS_SINE)
	standard_camera_tween.set_parallel(false)

func _get_standard_active_camera() -> Camera3D:
	if $player != null && $player.has_method("get_camera"):
		var active_camera = $player.get_camera() as Camera3D
		if active_camera != null:
			return active_camera
	return $camera_chessboard

func standard_clock_reset() -> void:
	standard_clock_remaining[0] = STANDARD_CLOCK_INITIAL_TIME
	standard_clock_remaining[1] = STANDARD_CLOCK_INITIAL_TIME
	standard_clock_active_group = -1
	standard_clock_running = false
	standard_clock_update_labels()

func standard_clock_set_active(group:int) -> void:
	standard_clock_active_group = group
	standard_clock_running = group == 0 || group == 1
	standard_clock_update_labels()

func standard_clock_set_active_from_board_turn() -> void:
	standard_clock_set_active($table_0/chessboard_standard.state.get_turn())

func standard_clock_pause() -> void:
	standard_clock_running = false
	standard_clock_active_group = -1
	standard_clock_update_labels()

func standard_clock_add_increment(group:int) -> void:
	if group != 0 && group != 1:
		return
	if standard_clock_remaining[group] > 0.0:
		standard_clock_remaining[group] += STANDARD_CLOCK_INCREMENT_TIME
	standard_clock_update_labels()

func standard_clock_update_labels() -> void:
	var player_group:int = standard_player_group
	if player_group != 0 && player_group != 1:
		player_group = 0
	var opponent_group:int = 1 - player_group
	standard_clock_player_label.text = standard_clock_format(standard_clock_remaining[player_group])
	standard_clock_opponent_label.text = standard_clock_format(standard_clock_remaining[opponent_group])
	standard_clock_player_label.modulate = standard_clock_label_color(player_group)
	standard_clock_opponent_label.modulate = standard_clock_label_color(opponent_group)

func standard_clock_format(seconds:float) -> String:
	var clamped_seconds:float = maxf(0.0, seconds)
	var whole_seconds:int = int(clamped_seconds)
	return "%02d:%02d" % [int(whole_seconds / 60), whole_seconds % 60]

func standard_clock_label_color(group:int) -> Color:
	if standard_clock_remaining[group] <= 0.0:
		return Color(1.0, 0.22, 0.16, 1.0)
	if standard_clock_running && standard_clock_active_group == group:
		return Color(0.65, 1.0, 0.5, 1.0)
	return Color(0.92, 0.96, 0.83, 1.0)

func interact_api_key() -> void:
	standard_show_api_key_screen()
	if standard_is_api_key_screen_visible():
		await standard_api_key_screen_closed

func interact_radio_music() -> void:
	radio_music_ensure_audio_player()
	var should_close:bool = false
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

func interact_pastor(custom_state:bool) -> void:
	var state:State = null
	if custom_state:
		var text_input_instance:TextInput = TextInput.create_text_input_instance("CHESS_FEN_PROMPT", STANDARD_CHESS_INITIAL_FEN)
		add_child(text_input_instance)
		await text_input_instance.confirmed
		state = Chess.parse(text_input_instance.text)
		if !is_instance_valid(state):
			return
	else:
		state = Chess.create_initial_state()
	Dialog.push_selection(["SELECTION_PLAY_AS_BLACK", "SELECTION_PLAY_AS_WHITE", "SELECTION_PLAY_AS_RANDOM", "SELECTION_CANCEL"], "", true, false)
	await Dialog.on_next
	if Dialog.selected == "SELECTION_CANCEL":
		return
	elif Dialog.selected == "SELECTION_PLAY_AS_WHITE":
		standard_player_group = 0
	elif Dialog.selected == "SELECTION_PLAY_AS_BLACK":
		standard_player_group = 1
	elif Dialog.selected == "SELECTION_PLAY_AS_RANDOM":
		standard_player_group = randi() % 2
	Dialog.push_selection([OPTION_CHESS_DIFFICULTY_STANDARD, OPTION_CHESS_DIFFICULTY_RELAX, OPTION_CANCEL], "", true, false)
	await Dialog.on_next
	if Dialog.selected == OPTION_CANCEL:
		return
	standard_relax_ai = Dialog.selected == OPTION_CHESS_DIFFICULTY_RELAX
	standard_reset_review_state(state)
	standard_refresh_review_prompt_side()
	if standard_player_group == 0:
		$table_0/chessboard_standard.rotation.y = 0
	else:
		$table_0/chessboard_standard.rotation.y = PI

	var from:int = Chess.c64_to_x88(Chess.first_bit($chessboard.state.get_bit(player_king)))
	if from != 0x54:
		$chessboard.execute_move(Chess.create(from, 0x54, 0))
		await $chessboard.animation_finished
		history_document.set_state($chessboard.state)
	$chessboard.set_enabled(false)
	$table_0/chessboard_standard.set_enabled(true)
	$chessboard/pieces/cheshire.set_position($chessboard.name_to_vector3("e2"))
	$chessboard/pieces/cheshire.set_rotation(Vector3(0, PI / 2, 0))
	$chessboard/pieces/cheshire.play_animation("thinking")
	standard_match_active = true
	standard_game_over = false
	standard_clock_view_active = false
	standard_clock_start_tick()
	$player.force_set_camera($camera_chessboard)
	standard_state_machine.change_state("start", {"state": state})
	await standard_game_finished

var game_premove_from:int = -1
var game_premove_to:int = -1

func game_premove_init() -> void:
	if game_premove_from == -1:
		var start_from:int = $table_0/chessboard_standard.state.get_bit(ord('A') if standard_player_group == 0 else ord('a'))
		$table_0/chessboard_standard.set_square_selection(start_from)
	elif game_premove_to == -1:
		var move_list:PackedInt32Array = Chess.generate_premove($table_0/chessboard_standard.state, standard_player_group)
		var selection:int = 0
		for iter:int in move_list:
			if Chess.from(iter) == game_premove_from:
				selection |= Chess.mask(Chess.x88_to_c64(Chess.to(iter)))
		$table_0/chessboard_standard.set_square_selection(selection)

func game_premove_pressed() -> void:
	var start_from:int = $table_0/chessboard_standard.state.get_bit(ord('A') if standard_player_group == 0 else ord('a'))
	if game_premove_from == -1 || game_premove_to != -1:
		game_premove_to = -1
		$table_0/chessboard_standard.clear_pointer("premove")
		var move_list:PackedInt32Array = Chess.generate_premove($table_0/chessboard_standard.state, standard_player_group)
		var selection:int = 0
		game_premove_from = $table_0/chessboard_standard.selected
		for iter:int in move_list:
			if Chess.from(iter) == game_premove_from:
				selection |= Chess.mask(Chess.x88_to_c64(Chess.to(iter)))
		$table_0/chessboard_standard.set_square_selection(selection)
	else:
		game_premove_to = $table_0/chessboard_standard.selected
		$table_0/chessboard_standard.draw_pointer("premove", Color(0.64, 0.051, 0.198, 1.0), game_premove_from, 1)
		$table_0/chessboard_standard.draw_pointer("premove", Color(0.639, 0.051, 0.196, 1.0), game_premove_to, 1)
		$table_0/chessboard_standard.set_square_selection(start_from)

func game_premove_cancel() -> void:
	var start_from:int = $table_0/chessboard_standard.state.get_bit(ord('A') if standard_player_group == 0 else ord('a'))
	game_premove_from = -1
	game_premove_to = -1
	$table_0/chessboard_standard.clear_pointer("premove")
	$table_0/chessboard_standard.set_square_selection(start_from)

func state_ready_in_game_start(_arg:Dictionary) -> void:
	standard_clock_reset()
	$table_0/chessboard_standard.state = _arg["state"]
	$table_0/chessboard_standard.remove_piece_set()
	$table_0/chessboard_standard.add_default_piece_set()
	standard_history_state.clear()
	standard_history_zobrist.clear()
	standard_history_event.clear()
	standard_history_move.clear()
	standard_initial_state = $table_0/chessboard_standard.state.duplicate()
	standard_history_document.new_page()
	standard_history_document.set_state($table_0/chessboard_standard.state)
	standard_show_review_tools(true)
	standard_refresh_review_tools(tr("MATCH_GAME_ACTIVE"))
	if $table_0/chessboard_standard.state.get_turn() != standard_player_group:
		standard_state_machine.change_state("opponent")
	else:
		standard_state_machine.change_state("player")

func state_ready_in_game_opponent(_arg:Dictionary) -> void:
	standard_clock_set_active_from_board_turn()
	standard_refresh_review_tools()
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_selection, game_premove_pressed)
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_empty, game_premove_cancel)
	standard_state_machine.state_signal_connect(standard_engine.search_finished, func() -> void:
		if STANDARD_DEBUG_ENGINE_STATS:
			print("score: ", standard_engine.get_score())
			print("deepest depth: ", standard_engine.get_deepest_depth())
			print("deepest ply: ", standard_engine.get_deepest_ply())
			print("evaluated_position: ", standard_engine.get_evaluated_position())
			print("beta_cutoff: ", standard_engine.get_beta_cutoff())
			print("transposition_table_cutoff: ", standard_engine.get_transposition_table_cutoff())
		standard_state_machine.change_state("move", {"move": standard_engine.get_search_result()})
	)
	if !standard_relax_ai:
		standard_engine.set_max_depth(20)
		standard_engine.set_quies(true)
	else:
		standard_engine.set_max_depth(2)
		standard_engine.set_quies(false)
	standard_engine.set_think_time(3)
	standard_engine.start_search($table_0/chessboard_standard.state, 1 - standard_player_group, standard_history_state, Callable())
	game_premove_init()

func state_ready_in_game_waiting(_arg:Dictionary) -> void:
	standard_clock_pause()
	standard_refresh_review_tools()
	standard_state_machine.state_signal_connect(standard_engine.search_finished, standard_state_machine.change_state.bind("opponent"))
	standard_engine.stop_search()

func state_ready_in_game_move(_arg:Dictionary) -> void:
	standard_refresh_review_tools()
	var moved_group:int = standard_clock_active_group
	standard_clock_pause()
	standard_clock_add_increment(moved_group)
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_selection, game_premove_pressed)
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_empty, game_premove_cancel)
	standard_history_document.push_move(_arg["move"])
	standard_history_state.push_back($table_0/chessboard_standard.state.duplicate())
	standard_history_zobrist.push_back($table_0/chessboard_standard.state.get_zobrist())
	standard_history_move.push_back(_arg["move"])
	var rollback_event:Dictionary = $table_0/chessboard_standard.execute_move(_arg["move"])
	standard_history_event.push_back(rollback_event)
	await $table_0/chessboard_standard.animation_finished
	if Chess.get_end_type($table_0/chessboard_standard.state) != "":
		standard_state_machine.change_state("game_end")
		return
	elif $table_0/chessboard_standard.state.get_turn() != standard_player_group:
		standard_state_machine.change_state("opponent")
	elif game_premove_from != -1 && game_premove_to != -1:
		$table_0/chessboard_standard.clear_pointer("premove")
		standard_state_machine.change_state("check_move", {"from": game_premove_from, "to": game_premove_to, "move_list": Chess.generate_valid_move($table_0/chessboard_standard.state, standard_player_group)})
		game_premove_from = -1
		game_premove_to = -1
	elif game_premove_from != -1 && ($table_0/chessboard_standard.mouse_hold || $table_0/chessboard_standard.button_input_hold):
		standard_state_machine.change_state("ready_to_move", {"from": game_premove_from})
		game_premove_from = -1
		game_premove_to = -1
	else:
		standard_state_machine.change_state("player")
		game_premove_from = -1
		game_premove_to = -1
	game_premove_init()

func standard_can_undo_now() -> bool:
	return standard_match_active \
		&& !standard_game_over \
		&& !standard_undo_in_progress \
		&& standard_state_machine.current_state == "player" \
		&& standard_history_event.size() > 1 \
		&& !standard_clock_view_active \
		&& !standard_ai_io_view_active \
		&& !standard_is_api_key_screen_visible()

func standard_undo_turn() -> void:
	if !standard_can_undo_now():
		if standard_state_machine.current_state == "player" && standard_history_event.size() <= 1:
			Dialog.push_selection(["SELECTION_LEAVE_GAME"], "HINT_TAKE_BACKED", false, false)
		standard_refresh_review_tools()
		return
	standard_undo_in_progress = true
	standard_refresh_review_tools()
	game_premove_from = -1
	game_premove_to = -1
	$table_0/chessboard_standard.clear_pointer("premove")
	$table_0/chessboard_standard.state = standard_history_state[-2]
	$table_0/chessboard_standard.set_square_selection($table_0/chessboard_standard.state.get_bit(ord('A') if standard_player_group == 0 else ord('a')))
	$table_0/chessboard_standard.receive_rollback_event(standard_history_event[-1])
	$table_0/chessboard_standard.receive_rollback_event(standard_history_event[-2])
	standard_history_zobrist.resize(standard_history_zobrist.size() - 2)
	standard_history_state.resize(standard_history_state.size() - 2)
	standard_history_event.resize(standard_history_event.size() - 2)
	standard_history_move.resize(standard_history_move.size() - 2)
	standard_history_document.rollback($table_0/chessboard_standard.state, 2)
	await $table_0/chessboard_standard.animation_finished
	standard_undo_in_progress = false
	if !standard_match_active || standard_game_over:
		standard_refresh_review_tools()
		return
	standard_clock_set_active_from_board_turn()
	$table_0/chessboard_standard.set_enabled(true)
	$table_0/chessboard_standard.set_square_selection($table_0/chessboard_standard.state.get_bit(ord('A') if standard_player_group == 0 else ord('a')))
	if standard_state_machine.current_state == "player":
		if standard_history_event.size() <= 1:
			Dialog.push_selection(["SELECTION_LEAVE_GAME"], "HINT_TAKE_BACKED", false, false)
		else:
			Dialog.push_selection(["SELECTION_TAKE_BACK", "SELECTION_LEAVE_GAME"], "HINT_TAKE_BACKED", false, false)
	standard_refresh_review_tools()

func state_ready_in_game_player(_arg:Dictionary) -> void:
	standard_clock_set_active_from_board_turn()
	standard_refresh_review_tools()
	var start_from:int = $table_0/chessboard_standard.state.get_bit(ord('A') if standard_player_group == 0 else ord('a'))
	standard_state_machine.state_signal_connect(Dialog.on_next, func () -> void:
		if Dialog.selected == "SELECTION_TAKE_BACK":
			standard_undo_turn()
		elif Dialog.selected == "SELECTION_LEAVE_GAME":
			standard_state_machine.change_state("game_end", {"leave_requested": true})
	)
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_selection, func () -> void:
		standard_state_machine.change_state("ready_to_move", {"from": $table_0/chessboard_standard.selected})
	)

	if standard_history_event.size() <= 1:
		Dialog.push_selection(["SELECTION_LEAVE_GAME"], "HINT_YOUR_TURN", false, false)
	else:
		Dialog.push_selection(["SELECTION_TAKE_BACK", "SELECTION_LEAVE_GAME"], "HINT_YOUR_TURN", false, false)
	$table_0/chessboard_standard.set_square_selection(start_from)

func state_exit_in_game_player() -> void:
	Dialog.clear()
	standard_refresh_review_tools()

func state_ready_in_game_ready_to_move(_arg:Dictionary) -> void:
	standard_refresh_review_tools()
	var move_list:PackedInt32Array = Chess.generate_valid_move($table_0/chessboard_standard.state, standard_player_group)
	var selection:int = 0
	var from:int = _arg["from"]
	var actor:Actor = $table_0/chessboard_standard.chessboard_piece[from]
	for iter:int in move_list:
		if Chess.from(iter) == from:
			selection |= Chess.mask(Chess.x88_to_c64(Chess.to(iter)))
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_selection, func () -> void:
		standard_state_machine.change_state("check_move", {"from": from, "to": $table_0/chessboard_standard.selected, "move_list": move_list})
	)
	standard_state_machine.state_signal_connect($table_0/chessboard_standard.click_empty, func () -> void:
		actor.idle()
		standard_state_machine.change_state("player")
	)
	actor.ready_to_move()
	$table_0/chessboard_standard.set_square_selection(selection)

func state_ready_in_game_check_move(_arg:Dictionary) -> void:
	standard_refresh_review_tools()
	var from:int = _arg["from"]
	var to:int = _arg["to"]
	var move_list:PackedInt32Array = Array(_arg["move_list"]).filter(func (move:int) -> bool: return from == Chess.from(move) && to == Chess.to(move))
	if move_list.size() == 0:
		standard_state_machine.change_state("player", {})
		return
	elif move_list.size() > 1:
		standard_state_machine.change_state("extra_move", {"move_list": move_list})
	else:
		standard_state_machine.change_state("move", {"move": move_list[0]})

func state_ready_in_game_extra_move(_arg:Dictionary) -> void:
	standard_refresh_review_tools()
	standard_extra_move_bottom_bar_was_visible = standard_review_bottom_bar.visible
	standard_review_bottom_bar.visible = false
	var decision_list:PackedStringArray = []
	var decision_to_move:Dictionary = {}
	for iter:int in _arg["move_list"]:
		decision_list.push_back("%c" % Chess.extra(iter))
		decision_to_move[decision_list[-1]] = iter
	decision_list.push_back(OPTION_CANCEL)
	standard_state_machine.state_signal_connect(Dialog.on_next, func () -> void:
		if Dialog.selected == OPTION_CANCEL || !decision_to_move.has(Dialog.selected):
			standard_state_machine.change_state("player")
		else:
			standard_state_machine.change_state("move", {"move": decision_to_move[Dialog.selected]})
	)
	Dialog.push_selection(decision_list, "HINT_EXTRA_MOVE", true, true)

func state_exit_in_game_extra_move() -> void:
	standard_review_bottom_bar.visible = standard_extra_move_bottom_bar_was_visible
	standard_extra_move_bottom_bar_was_visible = false
	standard_refresh_review_tools()

func state_ready_game_end(_arg:Dictionary) -> void:
	var end_type:String = String(_arg.get("end_type", ""))
	if end_type.is_empty():
		end_type = Chess.get_end_type($table_0/chessboard_standard.state)
	if bool(_arg.get("leave_requested", false)) || end_type.is_empty():
		standard_leave_game()
		return

	standard_engine.stop_search()
	standard_clock_pause()
	standard_game_over = true
	standard_clock_stop_tick()
	standard_clock_exit_view(true)
	if $player != null:
		$player.can_move = false
	standard_history_document.save_file()
	Dialog.clear()
	$table_0/chessboard_standard.set_enabled(false)
	$table_0/chessboard_standard.set_square_selection(0)
	$table_0/chessboard_standard.clear_pointer("premove")
	game_premove_from = -1
	game_premove_to = -1
	standard_prepare_game_end_review(end_type)
	if standard_should_show_game_end_review_button():
		standard_request_game_end_review()
	standard_leave_button.call_deferred("grab_focus")

func standard_leave_game() -> void:
	if !standard_match_active && !standard_game_over:
		standard_show_review_tools(false)
		return
	standard_archive_current_game_memory_on_leave()
	standard_engine.stop_search()
	standard_clock_pause()
	standard_clock_stop_tick()
	standard_match_active = false
	standard_game_over = false
	standard_clock_view_active = false
	standard_ai_io_view_active = false
	standard_ai_review_waiting = false
	standard_game_end_review_requested = false
	standard_undo_in_progress = false
	standard_review_end_type = ""
	standard_review_result = ""
	standard_review_text.text = ""
	standard_review_panel.visible = false
	standard_set_api_key_screen_visible(false)
	standard_show_review_tools(false)
	standard_reset_ai_io_paper()
	standard_history_document.save_file()
	$table_0/chessboard_standard.set_enabled(false)
	$table_0/chessboard_standard.set_square_selection(0)
	$table_0/chessboard_standard.clear_pointer("premove")
	game_premove_from = -1
	game_premove_to = -1
	$player.force_set_camera($camera)
	$player.can_move = true
	$chessboard.set_enabled(true)
	$chessboard/pieces/cheshire.play_animation("battle_idle")
	$chessboard/pieces/cheshire.set_position($chessboard.name_to_vector3("e3"))
	standard_game_finished.emit()

func standard_archive_current_game_memory_on_leave() -> void:
	if standard_game_end_review_requested:
		return
	if standard_chess_ai_wrapper == null:
		standard_initialize_chess_ai()
	if standard_chess_ai_wrapper == null || !standard_chess_ai_wrapper.is_available():
		return

	var end_type := standard_review_end_type
	var result := standard_review_result
	if result.is_empty():
		end_type = Chess.get_end_type($table_0/chessboard_standard.state)
		result = standard_game_result_text(end_type)
	if result.is_empty():
		result = tr("GAME_RESULT_LEFT")

	var session:Dictionary = standard_create_archive_game_session(result, end_type)
	standard_chess_ai_wrapper.archive_current_game_memory(session, result)

func standard_create_archive_game_session(result:String, end_type:String) -> Dictionary:
	return {
		"CurrentFEN": "",
		"InitialFEN": STANDARD_CHESS_INITIAL_FEN,
		"GameVariant": tr("CHESS_GAME_VARIANT"),
		"Board": [],
		"CurrentPlayer": 0,
		"HumanSide": standard_player_group,
		"HalfmoveClock": 0,
		"FullmoveNumber": int(standard_history_move.size() / 2) + 1,
		"MoveHistory": standard_build_archive_move_history(),
		"GameStatus": tr("GAME_STATUS_FINISHED"),
		"GameResult": result,
		"GameEndType": end_type,
		"LeftByPlayer": true,
		"TimeControl": "15+5",
		"TimeControlDescription": tr("CHESS_TIME_CONTROL_DESC"),
		"ClockInitialSeconds": STANDARD_CLOCK_INITIAL_TIME,
		"ClockIncrementSeconds": STANDARD_CLOCK_INCREMENT_TIME,
		"WhiteClockRemainingSeconds": standard_clock_remaining[0],
		"BlackClockRemainingSeconds": standard_clock_remaining[1],
		"WhiteClockRemaining": standard_clock_format(standard_clock_remaining[0]),
		"BlackClockRemaining": standard_clock_format(standard_clock_remaining[1]),
		"ClockActiveSide": standard_clock_active_group,
		"ClockRunning": standard_clock_running,
		"AIEnabled": true,
		"SessionId": str(Time.get_unix_time_from_system()),
	}

func standard_build_archive_move_history() -> Array:
	var history:Array = []
	for ply_index:int in range(standard_history_move.size()):
		var move:int = standard_history_move[ply_index]
		var coordinate:String = standard_move_coordinate(move)
		history.push_back({
			"FromIndex": Chess.x88_to_c64(Chess.from(move)),
			"ToIndex": Chess.x88_to_c64(Chess.to(move)),
			"Piece": "",
			"CapturedPiece": "",
			"Flags": 0,
			"ChineseNotation": coordinate,
			"CoordinateNotation": coordinate,
			"Side": ply_index % 2,
			"PlyIndex": ply_index + 1,
			"MoveNumber": int(ply_index / 2) + 1,
			"EvaluationScore": 0,
			"TeachingScore": 0,
			"BestMove": "",
		})
	return history

func standard_initialize_chess_ai() -> void:
	if standard_chess_ai_wrapper != null:
		return
	standard_chess_ai_wrapper = ChessAIWrapper.new()
	standard_chess_ai_wrapper.name = "standard_chess_ai_wrapper"
	standard_chess_ai_wrapper.ai_response.connect(standard_on_chess_ai_response)
	standard_chess_ai_wrapper.review_generated.connect(standard_on_chess_ai_review_generated)
	add_child(standard_chess_ai_wrapper)
	standard_refresh_review_prompt_side()

func standard_initialize_review_ui() -> void:
	get_viewport().size_changed.connect(standard_update_review_ui_layout)
	standard_update_review_ui_layout()
	standard_undo_button.pressed.connect(standard_undo_turn)
	standard_leave_button.pressed.connect(standard_leave_game)
	standard_api_key_button.pressed.connect(standard_show_api_key_screen)
	standard_api_key_input.placeholder_text = tr("API_KEY_PLACEHOLDER")
	if standard_review_button != null:
		standard_review_button.pressed.connect(standard_request_game_end_review)
		standard_review_button.visible = false
	standard_review_close_button.pressed.connect(func() -> void:
		standard_review_panel.visible = false
	)
	standard_api_key_save_button.pressed.connect(standard_save_api_key_from_input)
	standard_api_key_clear_button.pressed.connect(standard_clear_runtime_api_key)
	standard_api_key_back_button.pressed.connect(standard_hide_api_key_screen)
	standard_api_key_input.text_submitted.connect(func(_text:String) -> void:
		standard_save_api_key_from_input()
	)
	standard_set_api_key_screen_visible(false)
	standard_review_panel.visible = false
	standard_ai_io_view_active = false
	standard_reset_ai_io_paper()
	standard_show_review_tools(false)
	standard_refresh_api_key_status()

func standard_update_review_ui_layout() -> void:
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	var insets:Vector4 = UISafeArea.get_content_insets(get_viewport())
	var base_height:float = clampf(viewport_size.y * 0.08, 66.0, 92.0)
	var top_height:float = insets.y + base_height
	var bottom_height:float = insets.w + base_height

	standard_review_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	standard_review_top_bar.offset_left = 0.0
	standard_review_top_bar.offset_top = 0.0
	standard_review_top_bar.offset_right = 0.0
	standard_review_top_bar.offset_bottom = top_height
	standard_review_top_label.offset_top = insets.y
	standard_review_top_label.offset_bottom = 0.0

	standard_review_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, false)
	standard_review_bottom_bar.offset_left = 0.0
	standard_review_bottom_bar.offset_top = -bottom_height
	standard_review_bottom_bar.offset_right = 0.0
	standard_review_bottom_bar.offset_bottom = 0.0
	for control:Control in [standard_review_status_label, standard_undo_button, standard_leave_button, standard_api_key_button]:
		control.offset_top = 0.0
		control.offset_bottom = -insets.w
	if standard_review_button != null:
		standard_review_button.offset_top = 0.0
		standard_review_button.offset_bottom = -insets.w

func standard_reset_review_state(initial_state:State) -> void:
	standard_initial_state = initial_state.duplicate()
	standard_review_end_type = ""
	standard_review_result = ""
	standard_ai_review_waiting = false
	standard_game_end_review_requested = false
	standard_review_text.text = ""
	standard_review_panel.visible = false
	standard_ai_io_view_active = false
	standard_game_over = false
	standard_undo_in_progress = false
	standard_reset_ai_io_paper()
	standard_show_review_tools(false)
	standard_set_api_key_screen_visible(false)

func standard_prepare_game_end_review(end_type:String) -> void:
	standard_review_end_type = end_type
	standard_review_result = standard_game_result_text(end_type)
	standard_ai_review_waiting = false
	standard_game_end_review_requested = false
	standard_review_text.text = ""
	standard_review_panel.visible = false
	standard_ai_io_view_active = false
	standard_reset_ai_io_paper()
	standard_show_review_tools(!standard_review_end_type.is_empty())
	standard_refresh_review_tools()

func standard_should_show_game_end_review_button() -> bool:
	return standard_game_over && !standard_review_end_type.is_empty()

func standard_show_review_tools(should_show:bool) -> void:
	standard_review_top_bar.visible = should_show
	standard_review_bottom_bar.visible = should_show
	if !should_show:
		return
	standard_refresh_review_tools()

func standard_refresh_review_tools(status_text:String = "") -> void:
	if !standard_review_bottom_bar.visible && !standard_review_top_bar.visible:
		return
	if standard_review_top_bar.visible:
		standard_review_top_label.text = standard_review_status_text(status_text)
	if standard_review_bottom_bar.visible:
		standard_review_status_label.visible = false
		standard_review_status_label.text = ""
		standard_undo_button.text = tr("MATCH_UNDO")
		standard_undo_button.visible = true
		standard_undo_button.disabled = !standard_can_undo_now()
		standard_undo_button.modulate = Color(0.45, 0.45, 0.45, 1.0) if standard_undo_button.disabled else Color.WHITE
		standard_leave_button.text = tr("MATCH_LEAVE_GAME")
		standard_leave_button.disabled = false
		standard_api_key_button.text = tr("MATCH_API_KEY")
		standard_api_key_button.disabled = false
		if standard_review_button != null:
			standard_review_button.visible = standard_should_show_game_end_review_button()
			if standard_review_button.visible:
				if standard_ai_review_waiting:
					standard_review_button.text = tr("MATCH_REVIEW_GENERATING")
				elif standard_game_end_review_requested:
					standard_review_button.text = tr("MATCH_REVIEW_GENERATED")
				else:
					standard_review_button.text = tr("MATCH_GENERATE_REVIEW")
				standard_review_button.disabled = standard_ai_review_waiting
				standard_review_button.modulate = Color(0.45, 0.45, 0.45, 1.0) if standard_review_button.disabled else Color.WHITE

func standard_review_status_text(status_text:String = "") -> String:
	if !status_text.is_empty():
		return status_text
	if standard_ai_io_view_active:
		return tr("MATCH_REVIEW_TITLE")
	if standard_clock_view_active:
		return tr("MATCH_CLOCK")
	if standard_ai_review_waiting:
		return tr("MATCH_REVIEW_GENERATING_STATUS")
	if standard_game_end_review_requested:
		return tr("MATCH_REVIEW_GENERATED")
	if !standard_review_result.is_empty():
		return tr("MATCH_GAME_ENDED_WITH") % standard_review_result
	if standard_match_active && !standard_game_over:
		return tr("MATCH_GAME_ACTIVE")
	return tr("MATCH_GAME_OVER")

func standard_reset_ai_io_paper() -> void:
	standard_ai_io_entries.clear()
	if standard_ai_io_paper == null:
		return
	if standard_ai_io_paper.has_method("set_title_text"):
		standard_ai_io_paper.set_title_text("MATCH_REVIEW_TITLE")
	if standard_ai_io_paper.has_method("clear_entries"):
		standard_ai_io_paper.clear_entries()

func standard_set_ai_io_response(role:String, text:String) -> void:
	var clean_text:String = text.strip_edges()
	if clean_text.is_empty():
		return
	standard_ai_io_entries.clear()
	standard_ai_io_entries.push_back({
		"role": role,
		"text": clean_text,
	})
	if standard_ai_io_paper != null && standard_ai_io_paper.has_method("set_entries"):
		standard_ai_io_paper.set_entries(standard_ai_io_entries)

func standard_request_game_end_review() -> void:
	if !standard_should_show_game_end_review_button():
		standard_refresh_review_tools(tr("MATCH_REVIEW_NO_CHECKMATE"))
		return
	if standard_ai_review_waiting:
		standard_refresh_review_tools(tr("MATCH_REVIEW_GENERATING_STATUS"))
		return
	if standard_game_end_review_requested:
		standard_enter_ai_io_view()
		standard_refresh_review_tools()
		return
	if standard_chess_ai_wrapper == null:
		standard_initialize_chess_ai()
	if standard_chess_ai_wrapper == null || !standard_chess_ai_wrapper.is_available():
		standard_refresh_review_tools(tr("MATCH_AI_UNAVAILABLE"))
		return
	if !standard_chess_ai_wrapper.has_api_key():
		standard_refresh_review_tools(tr("MATCH_API_KEY_REQUIRED"))
		return

	var session:Dictionary = standard_create_game_session()
	standard_game_end_review_requested = true
	standard_ai_review_waiting = true
	standard_review_text.text = ""
	standard_review_panel.visible = false
	standard_reset_ai_io_paper()
	standard_refresh_review_tools()
	standard_chess_ai_wrapper.send_game_ended(session, standard_review_result)

func standard_on_chess_ai_response(response_type:String, content:String) -> void:
	if !standard_ai_review_waiting:
		return
	var clean_type:String = response_type.strip_edges()
	var clean_content:String = content.strip_edges()
	if clean_content.is_empty():
		return
	if clean_type.to_lower() != "error":
		return
	standard_ai_review_waiting = false
	standard_game_end_review_requested = false
	standard_review_text.text = "[%s]\n%s" % [clean_type, clean_content]
	standard_set_ai_io_response("error", standard_review_text.text)
	standard_refresh_review_tools(tr("MATCH_REVIEW_FAILED_RETRY"))

func standard_on_chess_ai_review_generated(review_content:String, _review_data:String) -> void:
	var clean_content:String = review_content.strip_edges()
	if clean_content.is_empty():
		return
	if !standard_game_end_review_requested && !standard_ai_review_waiting:
		return
	standard_ai_review_waiting = false
	standard_game_end_review_requested = true
	standard_review_text.text = clean_content
	standard_set_ai_io_response("review", clean_content)
	standard_refresh_review_tools()

func standard_create_game_session() -> Dictionary:
	var state:State = $table_0/chessboard_standard.state
	var current_fen:String = standard_ai_safe_fen(Chess.stringify(state))
	var initial_fen:String = standard_ai_safe_fen(Chess.stringify(standard_initial_state) if standard_initial_state != null else STANDARD_CHESS_INITIAL_FEN)
	return {
		"CurrentFEN": current_fen,
		"InitialFEN": initial_fen,
		"GameVariant": tr("CHESS_GAME_VARIANT"),
		"Board": standard_board_array_from_state(state),
		"CurrentPlayer": state.get_turn(),
		"HumanSide": standard_player_group,
		"HalfmoveClock": state.get_step_to_draw(),
		"FullmoveNumber": state.get_round(),
		"MoveHistory": standard_build_move_history(),
		"GameStatus": tr("GAME_STATUS_FINISHED"),
		"GameResult": standard_review_result,
		"GameEndType": standard_review_end_type,
		"TimeControl": "15+5",
		"TimeControlDescription": tr("CHESS_TIME_CONTROL_DESC"),
		"ClockInitialSeconds": STANDARD_CLOCK_INITIAL_TIME,
		"ClockIncrementSeconds": STANDARD_CLOCK_INCREMENT_TIME,
		"WhiteClockRemainingSeconds": standard_clock_remaining[0],
		"BlackClockRemainingSeconds": standard_clock_remaining[1],
		"WhiteClockRemaining": standard_clock_format(standard_clock_remaining[0]),
		"BlackClockRemaining": standard_clock_format(standard_clock_remaining[1]),
		"ClockActiveSide": standard_clock_active_group,
		"ClockRunning": standard_clock_running,
		"AIEnabled": true,
		"SessionId": str(Time.get_unix_time_from_system()),
	}

func standard_ai_safe_fen(fen:String) -> String:
	var cleaned:String = standard_ai_safe_text(fen)
	var parts:PackedStringArray = cleaned.split(" ", false)
	if parts.size() >= 4 && !standard_is_valid_fen_en_passant(parts[3]):
		parts[3] = "-"
	return " ".join(parts)

func standard_ai_safe_text(value:String) -> String:
	var output:String = ""
	for index:int in range(value.length()):
		var code:int = value.unicode_at(index)
		if code >= 32:
			output += value.substr(index, 1)
		elif code == 9:
			output += " "
	return output

func standard_is_valid_fen_en_passant(value:String) -> bool:
	if value == "-":
		return true
	if value.length() != 2:
		return false
	var file_code:int = value.unicode_at(0)
	var rank_code:int = value.unicode_at(1)
	return file_code >= ord("a") && file_code <= ord("h") && rank_code >= ord("1") && rank_code <= ord("8")

func standard_build_move_history() -> Array:
	var history:Array = []
	var replay_state:State = standard_initial_state.duplicate() if standard_initial_state != null else Chess.create_initial_state()
	for ply_index:int in range(standard_history_move.size()):
		var move:int = standard_history_move[ply_index]
		history.push_back(standard_create_move_record(replay_state, move, ply_index))
		Chess.apply_move(replay_state, move)
	return history

func standard_create_move_record(state_before:State, move:int, ply_index:int) -> Dictionary:
	var from:int = Chess.from(move)
	var to:int = Chess.to(move)
	var piece_code:int = state_before.get_piece(from)
	var captured_code:int = state_before.get_piece(to)
	var side:int = Chess.group(piece_code) if piece_code != 0 else ply_index % 2
	var flags:int = 0
	if captured_code != 0 || standard_is_en_passant_capture(state_before, move):
		flags |= 1
	var state_after:State = state_before.duplicate()
	Chess.apply_move(state_after, move)
	if Chess.get_end_type(state_after).begins_with("checkmate"):
		flags |= 4
	elif Chess.is_check(state_after, side):
		flags |= 2
	var coordinate:String = standard_move_coordinate(move)
	var move_name:String = Chess.get_move_name(state_before, move)
	var display_name:String = move_name if !move_name.is_empty() else coordinate
	if !coordinate.is_empty() && coordinate != display_name:
		display_name = "%s (%s)" % [display_name, coordinate]
	return {
		"FromIndex": Chess.x88_to_c64(from),
		"ToIndex": Chess.x88_to_c64(to),
		"Piece": standard_piece_text(piece_code),
		"CapturedPiece": standard_piece_text(captured_code),
		"Flags": flags,
		"ChineseNotation": display_name,
		"CoordinateNotation": coordinate,
		"Side": side,
		"PlyIndex": ply_index + 1,
		"MoveNumber": int(ply_index / 2) + 1,
		"EvaluationScore": 0,
		"TeachingScore": 0,
		"BestMove": "",
	}

func standard_board_array_from_state(state:State) -> Array:
	var board:Array = []
	for rank:int in range(8):
		for file:int in range(8):
			var square:int = rank * 16 + file
			board.push_back(standard_piece_text(state.get_piece(square)))
	return board

func standard_move_coordinate(move:int) -> String:
	var coordinate:String = "%s%s" % [Chess.x88_to_name(Chess.from(move)), Chess.x88_to_name(Chess.to(move))]
	var extra:int = Chess.extra(move)
	if extra != 0:
		coordinate += "%c" % (extra & 95)
	return coordinate

func standard_piece_text(piece_code:int) -> String:
	return "" if piece_code == 0 else "%c" % piece_code

func standard_is_en_passant_capture(state:State, move:int) -> bool:
	var from:int = Chess.from(move)
	var to:int = Chess.to(move)
	var piece_code:int = state.get_piece(from)
	return piece_code != 0 && (piece_code & 95) == ord("P") && to == state.get_en_passant()

func standard_game_result_text(end_type:String) -> String:
	match end_type:
		"checkmate_black":
			return tr("GAME_RESULT_BLACK_WIN")
		"checkmate_white":
			return tr("GAME_RESULT_WHITE_WIN")
		"timeout_white":
			return tr("GAME_RESULT_BLACK_WIN")
		"timeout_black":
			return tr("GAME_RESULT_WHITE_WIN")
		"stalemate_black", "stalemate_white", "50_moves", "not_enough_piece":
			return tr("GAME_RESULT_DRAW")
		_:
			return ""

func standard_refresh_review_prompt_side() -> void:
	if standard_chess_ai_wrapper == null || !standard_chess_ai_wrapper.is_available():
		return
	standard_chess_ai_wrapper.set_review_player_side(standard_player_group)

func standard_show_api_key_screen() -> void:
	if standard_chess_ai_wrapper == null:
		standard_initialize_chess_ai()
	standard_set_api_key_screen_visible(true)
	if $player != null:
		$player.can_move = false
	if standard_api_key_input != null:
		standard_api_key_input.text = ""
		standard_api_key_input.grab_focus()
	standard_refresh_api_key_status()

func standard_hide_api_key_screen() -> void:
	standard_set_api_key_screen_visible(false)
	if standard_api_key_input != null:
		standard_api_key_input.release_focus()
	if $player != null:
		$player.can_move = !standard_match_active || (!standard_clock_view_active && !standard_ai_io_view_active && !standard_game_over)

func standard_set_api_key_screen_visible(should_show:bool) -> void:
	var was_visible:bool = standard_api_key_screen.visible
	standard_api_key_screen.visible = should_show
	if was_visible && !should_show:
		standard_api_key_screen_closed.emit()

func standard_is_api_key_screen_visible() -> bool:
	return standard_api_key_screen != null && standard_api_key_screen.visible

func standard_save_api_key_from_input() -> void:
	var api_key:String = standard_api_key_input.text.strip_edges()
	if api_key.is_empty():
		standard_set_api_key_status(tr("API_KEY_EMPTY"))
		return
	if standard_chess_ai_wrapper == null:
		standard_initialize_chess_ai()
	if standard_chess_ai_wrapper == null || !standard_chess_ai_wrapper.is_available():
		standard_set_api_key_status(tr("MATCH_AI_UNAVAILABLE"))
		return
	if !standard_chess_ai_wrapper.set_api_key(api_key):
		standard_set_api_key_status(tr("API_KEY_SAVE_FAILED"))
		return
	standard_api_key_input.text = ""
	standard_set_api_key_status(tr("API_KEY_SAVED"))
	if standard_game_over && standard_should_show_game_end_review_button() && !standard_ai_review_waiting && !standard_game_end_review_requested:
		standard_request_game_end_review()

func standard_clear_runtime_api_key() -> void:
	if standard_chess_ai_wrapper == null:
		standard_initialize_chess_ai()
	if standard_chess_ai_wrapper == null || !standard_chess_ai_wrapper.is_available():
		standard_set_api_key_status(tr("MATCH_AI_UNAVAILABLE"))
		return
	if !standard_chess_ai_wrapper.clear_api_key():
		standard_set_api_key_status(tr("API_KEY_CLEAR_FAILED"))
		return
	standard_set_api_key_status(tr("API_KEY_CLEARED"))

func standard_refresh_api_key_status() -> void:
	if standard_chess_ai_wrapper != null && standard_chess_ai_wrapper.has_saved_api_key():
		standard_set_api_key_status(tr("API_KEY_LOADED"))
	elif standard_chess_ai_wrapper != null && standard_chess_ai_wrapper.has_api_key():
		standard_set_api_key_status(tr("API_KEY_READY"))
	else:
		standard_set_api_key_status(tr("API_KEY_WAITING"))

func standard_set_api_key_status(text:String) -> void:
	standard_api_key_status_label.text = text

func _filter_ready_to_move_selection(selection: PackedStringArray) -> PackedStringArray:
	var filtered := PackedStringArray()
	for option in selection:
		if option == "SELECTION_SETTINGS" or option == "SELECTION_STATUS":
			continue
		filtered.push_back(option)
	return filtered
