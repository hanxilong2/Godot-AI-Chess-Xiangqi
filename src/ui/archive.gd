extends CanvasLayer

const TEXT_FONT := preload("res://assets/fonts/FangZhengShuSongJianTi-1.ttf")

var template_list:Dictionary = {
	"printed": "res://scene/doc/printed_paper.tscn",
	"history": "res://scene/doc/history.tscn",
	"draft": "res://scene/doc/draft.tscn",
	"piece": "res://scene/doc/model.tscn",
	"inspectable": "res://scene/doc/model.tscn"
}

var document:Document = null
var document_list:PackedStringArray = []
var button_list:Array[Button] = []
var mouse_move_start:Vector2 = Vector2()
var mouse_moved:bool = false
var scroll_velocity:float = 0

@onready var texture_rect:TextureRect = $texture_rect
@onready var scroll_container:ScrollContainer = $texture_rect/scroll_container
@onready var document_browser:DocumentBrowser = $texture_rect/document_browser
@onready var button_close:Button = $texture_rect/button_close
@onready var action_bar:HBoxContainer = $texture_rect/h_box_container

func _ready() -> void:
	visible = false
	_prepare_close_button()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	button_close.connect("pressed", close)
	action_bar.get_node("button_rename").connect("pressed", rename_pressed)
	action_bar.get_node("button_add_empty").connect("pressed", add_empty_pressed)
	action_bar.get_node("button_duplicate").connect("pressed", duplicate_pressed)
	action_bar.get_node("button_delete").connect("pressed", delete_pressed)
	scroll_container.connect("gui_input", scroll_container_input)
	set_process(false)

func _exit_tree() -> void:
	_clear_document_instance()

func _process(_delta:float) -> void:
	scroll_container.scroll_vertical -= scroll_velocity
	scroll_velocity = max(0, abs(scroll_velocity) - 1) if scroll_velocity > 0 else -max(0, abs(scroll_velocity) - 1)

func open() -> void:
	set_process(true)
	_update_layout()
	button_close.grab_focus()
	_clear_document_instance()
	visible = true
	update_list()

func _clear_document_instance() -> void:
	document_browser.clear_document()
	if is_instance_valid(document):
		document.free()
	document = null

func update_list() -> void:
	for iter:Button in button_list:
		iter.queue_free()
	button_list.clear()
	document_list.clear()
	if !is_instance_valid(document):
		document_browser.close()
	var dir:DirAccess = DirAccess.open("user://archive/")
	if !dir:
		DirAccess.make_dir_absolute("user://archive/")
		dir = DirAccess.open("user://archive/")
	dir.list_dir_begin()
	var file_name:String = dir.get_next()
	while file_name != "":
		if !dir.current_is_dir() && _is_known_document_filename(file_name):
			document_list.push_back(file_name)
		file_name = dir.get_next()

	for iter:String in document_list:
		var button = Button.new()
		button.text = iter
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		button.add_theme_color_override("font_focus_color", Color(1, 1, 1, 1))
		button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
		button.add_theme_color_override("font_pressed_color", Color(0.6, 0.6, 0.6, 1))
		button.add_theme_font_size_override("font_size", 30)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		button.add_theme_font_override("font", preload("res://assets/fonts/FangZhengShuSongJianTi-1.ttf"))
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.connect("pressed", func () -> void:
			if !mouse_moved:
				open_document(iter)
		)
		button.connect("gui_input", button_input)
		scroll_container.get_node("v_box_container").add_child(button)
		button_list.push_back(button)

func button_input(event:InputEvent) -> void:
	if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_move_start = event.global_position
			mouse_moved = false

func scroll_container_input(event:InputEvent) -> void:
	if event is InputEventMouseMotion && (event.button_mask & MOUSE_BUTTON_MASK_LEFT) && (mouse_moved || event.global_position.distance_squared_to(mouse_move_start) > 400):
		mouse_moved = true
		scroll_velocity = event.relative.y

func open_document(filename:String) -> void:
	if is_instance_valid(document):
		document.save_file()
	_clear_document_instance()
	filename = filename.get_file()
	var filename_splited:PackedStringArray = filename.split(".")	# 模板.名称.json
	if filename_splited.size() < 2 or !template_list.has(filename_splited[0]):
		push_warning("Archive document has an unknown template: %s" % filename)
		update_list()
		return
	var template_scene := load(template_list[filename_splited[0]]) as PackedScene
	if template_scene == null:
		push_warning("Archive document template could not be loaded: %s" % filename_splited[0])
		update_list()
		return
	document = template_scene.instantiate()
	document.set_filename(filename)
	document.load_file()
	document_browser.set_document(document)
	document_browser.open()

func close() -> void:
	_clear_document_instance()
	document_browser.close()
	visible = false
	set_process(false)

func rename_pressed() -> void:
	if !is_instance_valid(document):
		return
	var filename_splited:PackedStringArray = document.get_filename().split(".")
	if filename_splited.size() < 2:
		return
	var text_input_instance:TextInput = TextInput.create_text_input_instance("ARCHIVE_RENAME_PROMPT", filename_splited[1])
	add_child(text_input_instance)
	await text_input_instance.confirmed
	var new_name:String = text_input_instance.text.strip_edges()
	if new_name.is_empty():
		return
	filename_splited[1] = new_name
	document.clear_file()
	document.set_filename(".".join(filename_splited))
	document.save_file()
	update_list()

func duplicate_pressed() -> void:
	if !is_instance_valid(document):
		return
	var filename_splited:PackedStringArray = document.get_filename().split(".")
	if filename_splited.size() < 2:
		return
	filename_splited[1] += "-dup"
	document.set_filename(".".join(filename_splited))
	document.save_file()
	update_list()

func delete_pressed() -> void:
	if !is_instance_valid(document):
		return
	document.clear_file()
	_clear_document_instance()
	update_list()

func add_empty_pressed() -> void:
	var template_scene := load(template_list["draft"]) as PackedScene
	if template_scene == null:
		return
	var new_document:Document = template_scene.instantiate()
	new_document.set_filename("draft.%d.json" % Time.get_unix_time_from_system())
	new_document.new_page()
	new_document.save_file()
	new_document.free()
	update_list()

func _is_known_document_filename(file_name:String) -> bool:
	if !file_name.ends_with(".json"):
		return false
	var filename_splited:PackedStringArray = file_name.get_file().split(".")
	return filename_splited.size() >= 2 && template_list.has(filename_splited[0])

func _prepare_close_button() -> void:
	button_close.text = "UI_BACK"
	button_close.add_theme_font_override("font", TEXT_FONT)
	button_close.add_theme_font_size_override("font_size", 24)
	button_close.custom_minimum_size = Vector2(96.0, 52.0)

func _update_layout() -> void:
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	var insets:Vector4 = UISafeArea.get_content_insets(get_viewport())
	var side_margin:float = clampf(viewport_size.x * 0.025, 20.0, 32.0)
	var top_margin:float = insets.y + side_margin
	var bottom_margin:float = insets.w + side_margin
	var left:float = insets.x + side_margin
	var right:float = insets.z + side_margin
	var left_width:float = clampf(viewport_size.x * 0.27, 240.0, 360.0)
	left_width = minf(left_width, maxf(viewport_size.x - left - right - 280.0, 160.0))
	var action_height:float = 58.0
	var list_top:float = top_margin + 72.0
	var action_top:float = viewport_size.y - bottom_margin - action_height

	button_close.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	button_close.offset_left = left
	button_close.offset_top = top_margin
	button_close.offset_right = left + button_close.custom_minimum_size.x
	button_close.offset_bottom = top_margin + button_close.custom_minimum_size.y

	scroll_container.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	scroll_container.offset_left = left
	scroll_container.offset_top = list_top
	scroll_container.offset_right = left + left_width
	scroll_container.offset_bottom = maxf(action_top - 16.0, list_top + 96.0)

	action_bar.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	action_bar.offset_left = left
	action_bar.offset_top = action_top
	action_bar.offset_right = left + left_width
	action_bar.offset_bottom = action_top + action_height

	document_browser.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	document_browser.offset_left = left + left_width + side_margin
	document_browser.offset_top = top_margin
	document_browser.offset_right = -right
	document_browser.offset_bottom = -bottom_margin
