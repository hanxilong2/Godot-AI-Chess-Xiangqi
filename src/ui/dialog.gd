extends CanvasLayer

signal on_next()

var selection:PackedStringArray = []
var selected:String = ""
var select_focus:int = -1
var waiting:bool = false
var click_anywhere:bool = false
var force_selection:bool = false
var click_cooldown:float = 0
var tween:Tween = null

@onready var top_bar:TextureRect = $texture_rect_top
@onready var bottom_bar:TextureRect = $texture_rect_bottom
@onready var top_label:RichTextLabel = $texture_rect_top/label
@onready var hint_left:RichTextLabel = $texture_rect_top/label_hint_left
@onready var hint_right:RichTextLabel = $texture_rect_top/label_hint_right
@onready var bottom_label:RichTextLabel = $texture_rect_bottom/label

func _ready() -> void:
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_sync_bar_visibility()
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_label.connect("meta_clicked", clicked_selection)

func _unhandled_input(event:InputEvent) -> void:
	if click_anywhere && !waiting:
		if event is InputEventMouseButton && event.button_index == MOUSE_BUTTON_LEFT && event.pressed && Time.get_unix_time_from_system() - click_cooldown >= 0.3:
			next()
			click_cooldown = Time.get_unix_time_from_system()
	if block_input():
		get_viewport().set_input_as_handled()

func push_dialog(text:String, title:String, blackscreen:bool = false, _click_anywhere:bool = false, _waiting:bool = false) -> void:
	if tween && tween.is_running():
		tween.kill()
	$texture_rect_full.visible = false
	if bottom_label.text != "" || top_label.text != "":
		clear()
	tween = create_tween()
	force_selection = false
	waiting = _waiting
	click_anywhere = _click_anywhere
	bottom_label.text = ""
	top_bar.visible = true
	bottom_bar.visible = true
	if blackscreen:
		tween.tween_property($texture_rect_full, "visible", true, 0)
	tween.tween_interval(0.3)
	tween.tween_property(bottom_label, "text", tr(text), 0)
	tween.tween_property(top_label, "text", tr(title), 0)
	tween.tween_property($texture_rect_full, "visible", false, 0)

func push_selection(_selection:PackedStringArray, title:String, _force_selection:bool = true, blackscreen:bool = false) -> void:
	var text:String = ""
	click_anywhere = false
	force_selection = _force_selection
	selection = _selection
	selected = ""
	text = selection_to_bbcode()
	if tween && tween.is_running():
		tween.kill()
	$texture_rect_full.visible = false
	if bottom_label.text != "" || top_label.text != "":
		clear()
	tween = create_tween()
	top_bar.visible = true
	bottom_bar.visible = true
	if blackscreen:
		tween.tween_property($texture_rect_full, "visible", true, 0)
	tween.tween_interval(0.3)
	tween.tween_property(bottom_label, "text", text, 0)
	tween.tween_property(top_label, "text", tr(title), 0)
	tween.tween_property($texture_rect_full, "visible", false, 0)

func set_hint_left(text:String) -> void:
	hint_left.text = text
	_sync_bar_visibility()

func set_hint_right(text:String) -> void:
	hint_right.text = text
	_sync_bar_visibility()

func clear() -> void:
	if tween && tween.is_running():
		tween.kill()
	bottom_label.text = ""
	top_label.text = ""
	$texture_rect_full.visible = false
	click_anywhere = false
	force_selection = false
	waiting = false
	selection.clear()
	select_focus = -1
	_sync_bar_visibility()

func next() -> void:
	if selection.size() > 0:
		if select_focus >= 0 and select_focus < selection.size():
			selected = selection[select_focus]
		elif selection.size() == 1 and !selection.has(selected):
			selected = selection[0]
		elif !selection.has(selected):
			selected = ""
	bottom_label.text = ""
	top_label.text = ""
	click_anywhere = false
	force_selection = false
	waiting = false
	selection.clear()
	select_focus = -1
	_sync_bar_visibility()
	on_next.emit.call_deferred()

func direction(axis:int) -> void:
	if !selection.size():
		return
	if select_focus == -1:
		select_focus = 0 if axis == 1 else selection.size() - 1
	else:
		select_focus += axis
		select_focus = (select_focus + selection.size()) % selection.size()
	selected = selection[select_focus]
	bottom_label.text = selection_to_bbcode()

func cancel_focus() -> void:
	select_focus = -1
	bottom_label.text = selection_to_bbcode()

func clicked_selection(_selected:String) -> void:
	selected = _selected
	next()

func selection_to_bbcode() -> String:
	var entries:PackedStringArray = []
	for i:int in selection.size():
		if i == select_focus:
			entries.push_back("[url=\"" + selection[i] + "\"][color=red]" + tr(selection[i]) + "[/color][/url]")
		else:
			entries.push_back("[url=\"" + selection[i] + "\"]" + tr(selection[i]) + "[/url]")
	return "[center]" + "    ".join(entries) + "[/center]"

func block_input() -> bool:
	return click_anywhere || force_selection || Time.get_unix_time_from_system() - click_cooldown < 0.3

func _sync_bar_visibility() -> void:
	top_bar.visible = !top_label.text.is_empty() || !hint_left.text.is_empty() || !hint_right.text.is_empty()
	bottom_bar.visible = !bottom_label.text.is_empty()

func _update_layout() -> void:
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	var insets:Vector4 = UISafeArea.get_content_insets(get_viewport())
	var display_insets:Vector4 = UISafeArea.get_display_safe_insets(get_viewport())
	var text_height:float = clampf(viewport_size.y * 0.105, 68.0, 96.0)
	var top_bar_height:float = maxf(insets.y, display_insets.y) + text_height
	var bottom_bar_height:float = maxf(insets.w, display_insets.w) + text_height

	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	top_bar.offset_left = 0.0
	top_bar.offset_top = 0.0
	top_bar.offset_right = 0.0
	top_bar.offset_bottom = top_bar_height

	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, false)
	bottom_bar.offset_left = 0.0
	bottom_bar.offset_top = -bottom_bar_height
	bottom_bar.offset_right = 0.0
	bottom_bar.offset_bottom = 0.0

	for label:RichTextLabel in [hint_left, hint_right, top_label]:
		label.offset_top = maxf(insets.y, display_insets.y)
		label.offset_bottom = 0.0
	bottom_label.offset_top = 0.0
	bottom_label.offset_bottom = -maxf(insets.w, display_insets.w)
