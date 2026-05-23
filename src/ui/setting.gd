extends CanvasLayer

const TEXT_FONT := preload("res://assets/fonts/FangZhengShuSongJianTi-1.ttf")
const SETTINGS_FILE_PATH := "user://settings.json"
const DESIGN_RESOLUTION := Vector2i(1152, 648)
const DESIGN_ASPECT := float(DESIGN_RESOLUTION.x) / float(DESIGN_RESOLUTION.y)
const TAB_TITLE_TRANSLATION_KEYS:PackedStringArray = [
	"SETTINGS_TAB_GAME",
	"SETTINGS_TAB_VIDEO",
	"SETTINGS_TAB_ACCESSIBILITY",
	"SETTINGS_TAB_MEMORY"
]
const LEGACY_RESOLUTIONS := [
	Vector2i(800, 600),
	Vector2i(1024, 600),
	Vector2i(1152, 648),
	Vector2i(1440, 900),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

var resolutions:Array[Vector2i] = [
	Vector2i(800, 450),
	Vector2i(1024, 576),
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160)
]

var languages:Dictionary[String, String] = {
	"en": "English",
	"zh_CN": "简体中文"
}

var language_codes:PackedStringArray = ["en", "zh_CN"]

var axis:Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1)
]

var table:Dictionary = {}

@onready var texture_rect:TextureRect = $texture_rect
@onready var label_title:Label = $texture_rect/label_title
@onready var tab_container:TabContainer = $texture_rect/tab_container
@onready var button_close:Button = $texture_rect/button_close
@onready var resolution_input:OptionButton = $texture_rect/tab_container/video/h_box_container/v_box_container_left/margin_container_resolution/h_box_container/option_button
@onready var fullscreen_input:CheckBox = $texture_rect/tab_container/video/h_box_container/v_box_container_left/margin_container_fullscreen/h_box_container/check_box
@onready var fps_input:OptionButton = $texture_rect/tab_container/video/h_box_container/v_box_container_left/margin_container_fps/h_box_container/option_button
@onready var vsync_input:CheckBox = $texture_rect/tab_container/video/h_box_container/v_box_container_left/margin_container_vsync/h_box_container/check_box
@onready var language_input:OptionButton = $texture_rect/tab_container/accessibility/v_box_container/margin_container_language/h_box_container/option_button
@onready var relax_input:CheckBox = $texture_rect/tab_container/game/v_box_container/margin_container_relax/v_box_container/h_box_container/check_box
@onready var clear_chess_memory_input:Button = $texture_rect/tab_container/files/v_box_container/margin_container_clean_chess_memory/h_box_container/button
@onready var clear_xiangqi_memory_input:Button = $texture_rect/tab_container/files/v_box_container/margin_container_clean_xiangqi_memory/h_box_container/button

func _ready() -> void:
	var current_resolution:Vector2i = _to_design_aspect_size(get_viewport().size)
	if !resolutions.has(current_resolution):
		resolutions.push_front(current_resolution)
	get_viewport().size_changed.connect(_update_layout)
	_prepare_close_button()
	_update_layout()

	for iter:Vector2i in resolutions:
		resolution_input.add_item("%d * %d" % [iter.x, iter.y])
	for key:String in language_codes:
		language_input.add_item(languages[key])
	load_file()

	resolution_input.connect("item_selected", set_resolution)
	fullscreen_input.connect("toggled", set_fullscreen)
	fps_input.connect("item_selected", set_fps)
	vsync_input.connect("toggled", set_vsync)
	language_input.connect("item_selected", set_language)
	relax_input.connect("toggled", set_relax)
	clear_chess_memory_input.connect("pressed", set_clear_chess_memory)
	clear_xiangqi_memory_input.connect("pressed", set_clear_xiangqi_memory)
	button_close.connect("pressed", close)

	var resolution_index:int = _saved_resolution_index()
	resolution_input.select(resolution_index)
	set_resolution(resolution_index)

	var fullscreen:bool = bool(table.get_or_add("fullscreen", false))
	fullscreen_input.set_pressed_no_signal(fullscreen)
	set_fullscreen(fullscreen)

	var fps_index:int = clampi(int(table.get_or_add("fps", 6)), 0, 6)
	fps_input.select(fps_index)
	set_fps(fps_index)

	var vsync:bool = bool(table.get_or_add("vsync", true))
	vsync_input.set_pressed_no_signal(vsync)
	set_vsync(vsync)

	var language_index:int = clampi(int(table.get_or_add("language", _default_language_index())), 0, language_codes.size() - 1)
	language_input.select(language_index)
	set_language(language_index)

	var relax:bool = bool(table.get_or_add("relax", false))
	relax_input.set_pressed_no_signal(relax)
	set_relax(relax)

	_hide_game_settings_tab()
	visible = false

func open() -> void:
	_hide_game_settings_tab()
	visible = true
	_update_layout()
	tab_container.get_tab_bar().grab_focus()

func close() -> void:
	save_file()
	visible = false

func load_file() -> void:
	var file:FileAccess = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if !is_instance_valid(file):
		return
	var parsed:Variant = JSON.parse_string(file.get_as_text())
	table = parsed if parsed is Dictionary else {}
	file.close()

func save_file() -> void:
	var file:FileAccess = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if !is_instance_valid(file):
		return
	file.store_string(JSON.stringify(table))
	file.close()

func get_value(key:String, default_value:Variant = null) -> Variant:
	return table.get(key, _default_setting_value(key) if default_value == null else default_value)

func set_resolution(index:int) -> void:
	index = clampi(index, 0, resolutions.size() - 1)
	table.set("resolution", index)
	var size:Vector2i = resolutions[index]
	table.set("resolution_size", [size.x, size.y])
	_apply_window_resolution(index)

func set_fullscreen(toggled_on:bool) -> void:
	table.set("fullscreen", toggled_on)
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_window_resolution(int(table.get("resolution", 0)))

func set_fps(index:int) -> void:
	index = clampi(index, 0, 6)
	table.set("fps", index)
	match index:
		0:
			Engine.max_fps = 10
		1:
			Engine.max_fps = 30
		2:
			Engine.max_fps = 60
		3:
			Engine.max_fps = 90
		4:
			Engine.max_fps = 120
		5:
			Engine.max_fps = 144
		6:
			Engine.max_fps = -1

func set_vsync(toggled_on:bool) -> void:
	table.set("vsync", toggled_on)
	if toggled_on:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSyncMode.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSyncMode.VSYNC_DISABLED)

func set_language(index:int) -> void:
	index = clampi(index, 0, language_codes.size() - 1)
	table.set("language", index)
	TranslationServer.set_locale(language_codes[index])
	_refresh_tab_titles()

func set_relax(toggled_on:bool) -> void:
	table.set("relax", toggled_on)

func set_clear_chess_memory() -> void:
	_clear_ai_memory(
		PackedStringArray(["ClearChessMemory", "clear_chess_memory"]),
		"SETTINGS_CLEAR_CHESS_MEMORY_SUCCESS",
		"SETTINGS_CLEAR_CHESS_MEMORY_FAILED"
	)

func set_clear_xiangqi_memory() -> void:
	_clear_ai_memory(
		PackedStringArray(["ClearXiangqiMemory", "clear_xiangqi_memory"]),
		"SETTINGS_CLEAR_XIANGQI_MEMORY_SUCCESS",
		"SETTINGS_CLEAR_XIANGQI_MEMORY_FAILED"
	)

func _clear_ai_memory(method_names:PackedStringArray, success_key:String, failed_key:String) -> void:
	var success:bool = false
	var ai_module:Node = get_node_or_null("/root/ChessAI")
	if ai_module != null:
		for method_name:String in method_names:
			if ai_module.has_method(method_name):
				success = bool(ai_module.call(method_name))
				break
	var toast_key:String = success_key if success else failed_key
	var toast:Toast = Toast.create_instance(toast_key)
	add_child(toast)

func _hide_game_settings_tab() -> void:
	if tab_container.get_tab_count() == 0:
		return
	tab_container.set_tab_hidden(0, true)
	if tab_container.current_tab == 0 && tab_container.get_tab_count() > 1:
		tab_container.current_tab = 1

func _refresh_tab_titles() -> void:
	for index:int in range(mini(tab_container.get_tab_count(), TAB_TITLE_TRANSLATION_KEYS.size())):
		tab_container.set_tab_title(index, tr(TAB_TITLE_TRANSLATION_KEYS[index]))

func _prepare_close_button() -> void:
	button_close.text = "UI_BACK"
	button_close.add_theme_font_override("font", TEXT_FONT)
	button_close.add_theme_font_size_override("font_size", 24)
	button_close.custom_minimum_size = Vector2(96.0, 52.0)
	button_close.mouse_filter = Control.MOUSE_FILTER_STOP
	button_close.z_index = 10

func _apply_window_resolution(index:int) -> void:
	var size:Vector2i = resolutions[clampi(index, 0, resolutions.size() - 1)]
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen:int = DisplayServer.window_get_current_screen()
	var usable_rect:Rect2i = DisplayServer.screen_get_usable_rect(screen)
	size = _fit_size_to_usable_rect(size, usable_rect)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable_rect.position + (usable_rect.size - size) / 2)
	call_deferred("_update_layout")

func _update_layout() -> void:
	var insets:Vector4 = UISafeArea.get_content_insets(get_viewport())
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	var side_margin:float = 24.0
	var close_width:float = clampf(viewport_size.x * 0.09, 96.0, 128.0)
	var close_height:float = clampf(viewport_size.y * 0.08, 52.0, 64.0)
	var title_height:float = clampf(viewport_size.y * 0.12, 60.0, 84.0)
	var header_height:float = clampf(viewport_size.y * 0.18, 104.0, 132.0)

	texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	texture_rect.offset_left = 0.0
	texture_rect.offset_top = 0.0
	texture_rect.offset_right = 0.0
	texture_rect.offset_bottom = 0.0

	button_close.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	button_close.offset_left = insets.x + side_margin
	button_close.offset_top = insets.y + 18.0
	button_close.offset_right = button_close.offset_left + close_width
	button_close.offset_bottom = button_close.offset_top + close_height

	label_title.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	label_title.scale = Vector2.ONE
	label_title.offset_left = insets.x + side_margin + close_width + 18.0
	label_title.offset_top = insets.y + 18.0
	label_title.offset_right = -(insets.z + side_margin)
	label_title.offset_bottom = label_title.offset_top + title_height

	tab_container.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	tab_container.offset_left = insets.x
	tab_container.offset_top = insets.y + header_height
	tab_container.offset_right = -insets.z
	tab_container.offset_bottom = -(insets.w + 24.0)

func _saved_resolution_index() -> int:
	if table.has("resolution_size"):
		var saved_size:Variant = table.get("resolution_size")
		if saved_size is Array && saved_size.size() >= 2:
			var size:Vector2i = _to_design_aspect_size(Vector2i(int(saved_size[0]), int(saved_size[1])))
			var size_index:int = resolutions.find(size)
			if size_index != -1:
				return size_index
	if table.has("resolution"):
		var legacy_index:int = int(table.get("resolution"))
		if !table.has("resolution_size") && legacy_index >= 0 && legacy_index < LEGACY_RESOLUTIONS.size():
			var legacy_size:Vector2i = _to_design_aspect_size(LEGACY_RESOLUTIONS[legacy_index])
			var migrated_index:int = resolutions.find(legacy_size)
			if migrated_index != -1:
				return migrated_index
			return _default_resolution_index()
		return clampi(legacy_index, 0, resolutions.size() - 1)
	return _default_resolution_index()

func _default_resolution_index() -> int:
	var current_index:int = resolutions.find(_to_design_aspect_size(get_viewport().size))
	if current_index != -1:
		return current_index
	var design_index:int = resolutions.find(DESIGN_RESOLUTION)
	if design_index != -1:
		return design_index
	return 0

func _to_design_aspect_size(size:Vector2i) -> Vector2i:
	if size.x <= 0 || size.y <= 0:
		return DESIGN_RESOLUTION
	var fitted:Vector2 = Vector2(size)
	var current_aspect:float = fitted.x / fitted.y
	if current_aspect > DESIGN_ASPECT:
		fitted.x = fitted.y * DESIGN_ASPECT
	else:
		fitted.y = fitted.x / DESIGN_ASPECT
	return Vector2i(maxi(roundi(fitted.x), 1), maxi(roundi(fitted.y), 1))

func _fit_size_to_usable_rect(size:Vector2i, usable_rect:Rect2i) -> Vector2i:
	var fitted:Vector2 = Vector2(_to_design_aspect_size(size))
	var usable_size:Vector2 = Vector2(usable_rect.size)
	if fitted.x > usable_size.x:
		fitted.x = usable_size.x
		fitted.y = fitted.x / DESIGN_ASPECT
	if fitted.y > usable_size.y:
		fitted.y = usable_size.y
		fitted.x = fitted.y * DESIGN_ASPECT
	return Vector2i(maxi(roundi(fitted.x), 320), maxi(roundi(fitted.y), 180))

func _default_language_index() -> int:
	var locale:String = TranslationServer.get_locale()
	var index:int = language_codes.find(locale)
	if index != -1:
		return index
	if locale.begins_with("zh"):
		return language_codes.find("zh_CN")
	return 0

func _default_setting_value(key:String) -> Variant:
	match key:
		"resolution":
			return _default_resolution_index()
		"fullscreen":
			return false
		"fps":
			return 6
		"vsync":
			return true
		"language":
			return _default_language_index()
		"relax":
			return false
	return null
