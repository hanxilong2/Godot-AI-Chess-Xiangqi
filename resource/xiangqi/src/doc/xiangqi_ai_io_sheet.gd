extends Control
class_name XiangqiAiIoSheet

signal chat_submitted(message: String)

@export var title_text := "XQ_AI_IO_TITLE"
@export var max_entries_per_page := 1

const PAGE_PANEL_MIN_HEIGHT := 1180.0
const EMPTY_FONT_SIZE := 44
const ROLE_FONT_SIZE := 38
const RESPONSE_FONT_SIZE := 80
const RESPONSE_LINE_SPACING := 8
const CHAT_FONT_SIZE := 58
const CHAT_PAIR_FONT_SIZE := 48
const CHAT_LINE_SPACING := 10
const INPUT_PANEL_SCALE := Vector2(0.8, 0.8)
const INPUT_PANEL_MIN_SIZE := Vector2(420.0, 520.0)
const INPUT_SEND_ROW_HEIGHT := 110.0
const INPUT_BUTTON_WIDTH := 260.0
const SEND_BUTTON_RECT := Rect2(650.0, 1180.0, 310.0, 120.0)
const BUTTON_HIT_PADDING := Vector2(56.0, 42.0)
const ENTRY_PANEL_MARGIN_X := 28.0
const ENTRY_PANEL_MARGIN_Y := 24.0
const ENTRY_BOX_SEPARATION := 18.0
const ENTRY_TEXT_WIDTH_FALLBACK := 900.0
const ENTRY_TEXT_HEIGHT_SAFETY := 24.0
const ENTRY_CONTINUED_SUFFIX := "AI_IO_CONTINUED"

var _entries: Array = []
var _chat_pages: Array = []
var _entries_signature := ""
var _note_after_chat_count := 0
var _draft_text := ""
var _input_focused := false
var _current_page := 0
var _draft_edit: TextEdit = null
var _send_button: Button = null
var _input_panel: Control = null
var _pages_cache: Array = []
var _pages_dirty := true
var _pages_cache_width := -1.0
var _note_pages_cache: Array = []
var _note_pages_dirty := true
var _chat_fragment_cache: Array = []

@onready var title_label: Label = $margin/frame/v_box/title_label
@onready var subtitle_label: Label = $margin/frame/v_box/subtitle_label
@onready var rows_container: VBoxContainer = $margin/frame/v_box/rows_container

func _ready() -> void:
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_mark_pages_dirty(true, true)
		_refresh_rows(false)

func set_title_text(value: String) -> void:
	title_text = value
	if is_node_ready():
		title_label.text = tr(title_text)

func set_entries(entries: Array) -> void:
	var next_entries := entries.duplicate(true)
	var next_signature := JSON.stringify(next_entries)
	var entries_changed := next_signature != _entries_signature
	_entries = next_entries
	_entries_signature = next_signature
	if entries_changed:
		_mark_pages_dirty(true)
	if entries_changed and !_entries.is_empty():
		_note_after_chat_count = _chat_pages.size()
	if _entries.is_empty():
		_current_page = mini(_current_page, get_page_count() - 1)
		if is_node_ready():
			_refresh_rows()
		return
	show_latest_note_page()

func add_entry(role: String, text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	_entries.push_back({
		"role": role,
		"text": clean_text,
	})
	_entries_signature = JSON.stringify(_entries)
	_note_after_chat_count = _chat_pages.size()
	_mark_pages_dirty(true)
	show_latest_note_page()

func clear_entries() -> void:
	_entries.clear()
	_chat_pages.clear()
	_entries_signature = ""
	_note_after_chat_count = 0
	_draft_text = ""
	_draft_edit = null
	_send_button = null
	_input_panel = null
	_input_focused = false
	_current_page = 0
	_mark_pages_dirty(true, true)
	if is_node_ready():
		_refresh_rows(false)

func set_chat_response(role: String, text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	if !_chat_pages.is_empty():
		var last_page := _chat_pages[_chat_pages.size() - 1] as Dictionary
		if last_page != null and String(last_page.get("role", "")) == "chat_pair" and String(last_page.get("answer_role", "")) == "chat_waiting":
			last_page["answer_role"] = role
			last_page["answer"] = clean_text
			_chat_pages[_chat_pages.size() - 1] = last_page
			_invalidate_chat_fragment(_chat_pages.size() - 1)
			_mark_pages_dirty()
			show_latest_chat_page()
			return
	_chat_pages.push_back(_make_chat_pair_entry("", role, clean_text))
	_chat_fragment_cache.push_back({})
	_mark_pages_dirty()
	show_latest_chat_page()

func handle_sheet_click(viewport_position: Vector2) -> bool:
	if !_is_input_page():
		_input_focused = false
		return false
	if !_input_panel_contains_point(viewport_position):
		_input_focused = false
		return false
	_input_focused = true
	if _button_contains_point(_send_button, SEND_BUTTON_RECT, viewport_position):
		_submit_draft()
	else:
		_focus_draft_edit()
	return true

func handle_key_event(event: InputEvent) -> bool:
	if !_is_input_page():
		return false
	var key_event := event as InputEventKey
	if key_event == null or !key_event.pressed:
		return false
	_input_focused = true
	match key_event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if key_event.shift_pressed:
				_focus_draft_edit()
				return false
			_submit_draft()
			return true
		KEY_ESCAPE:
			return false
		KEY_PAGEUP, KEY_PAGEDOWN, KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			return false

	_focus_draft_edit()
	return false

func is_chat_input_page() -> bool:
	return _is_input_page()

func set_current_page(page_index: int) -> void:
	_current_page = clampi(page_index, 0, get_page_count() - 1)
	if is_node_ready():
		_refresh_rows()

func show_latest_page() -> void:
	_current_page = get_page_count() - 1
	if is_node_ready():
		_refresh_rows()

func show_latest_chat_page() -> void:
	var chat_page := _find_chat_page_index(_chat_pages.size() - 1)
	if chat_page >= 0:
		_current_page = chat_page
	else:
		_current_page = get_page_count() - 1
	if is_node_ready():
		_refresh_rows()

func show_latest_note_page() -> void:
	var note_page := _find_latest_note_page_index()
	_current_page = note_page if note_page >= 0 else maxi(0, get_page_count() - 1)
	if is_node_ready():
		_refresh_rows()

func turn_page(delta: int) -> bool:
	var previous_page := _current_page
	set_current_page(_current_page + delta)
	return previous_page != _current_page

func can_turn_page(delta: int) -> bool:
	var target_page := _current_page + delta
	return target_page >= 0 and target_page < get_page_count()

func get_entry_count() -> int:
	return _entries.size()

func get_page_count() -> int:
	return _page_descriptors().size()

func get_current_page() -> int:
	return _current_page

func _refresh() -> void:
	title_label.text = tr(title_text)
	_refresh_rows()

func _refresh_rows(sync_draft: bool = true) -> void:
	if sync_draft:
		_sync_draft_from_text_edit()
	_draft_edit = null
	_send_button = null
	_input_panel = null
	for child in rows_container.get_children():
		child.queue_free()

	_refresh_subtitle()

	var page := _page_descriptor(_current_page)
	var page_type := String(page.get("type", "cover"))

	if page_type == "cover":
		rows_container.add_child(_make_cover_view())
		return
	if page_type == "note":
		for entry_variant in _visible_entries(page):
			var entry := entry_variant as Dictionary
			if entry == null:
				continue
			rows_container.add_child(_make_entry_view(entry))
		return
	if page_type == "input":
		rows_container.add_child(_make_input_view())
		return

	var chat_entry := _chat_page_entry(page)
	if !chat_entry.is_empty():
		rows_container.add_child(_make_chat_pair_view(chat_entry))

func _refresh_subtitle() -> void:
	subtitle_label.text = tr("AI_IO_PAGE_FORMAT") % [_current_page + 1, get_page_count()]
	subtitle_label.visible = get_page_count() > 1

func _visible_entries(page: Dictionary) -> Array:
	var page_entries_variant: Variant = page.get("entries", null)
	if page_entries_variant is Array:
		return (page_entries_variant as Array).duplicate(true)
	if _entries.is_empty():
		return []
	var start_index := int(page.get("entry_start", 0))
	var end_index := mini(start_index + max_entries_per_page, _entries.size())
	return _entries.slice(start_index, end_index)

func _make_cover_view() -> PanelContainer:
	var panel := _make_entry_panel(Color(0.79, 0.73, 0.63, 0.07))
	panel.custom_minimum_size = Vector2(0.0, PAGE_PANEL_MIN_HEIGHT)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 92)
	label.add_theme_color_override("font_color", Color(0.25, 0.21, 0.16, 1.0))
	label.text = tr(title_text)
	panel.add_child(label)
	return panel

func _make_input_view() -> Control:
	var wrapper := CenterContainer.new()
	wrapper.custom_minimum_size = Vector2(0.0, PAGE_PANEL_MIN_HEIGHT)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var panel := _make_entry_panel(Color(0.79, 0.73, 0.63, 0.05))
	var input_size := _input_panel_target_size()
	panel.custom_minimum_size = input_size
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_input_panel = panel
	wrapper.add_child(panel)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	_draft_edit = TextEdit.new()
	_draft_edit.name = "draft_text_edit"
	_draft_edit.text = _draft_text
	_draft_edit.placeholder_text = tr("AI_IO_CHAT_PLACEHOLDER")
	_draft_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draft_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_draft_edit.custom_minimum_size = Vector2(0.0, _input_draft_height(input_size))
	_draft_edit.focus_mode = Control.FOCUS_CLICK
	_draft_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_draft_edit.virtual_keyboard_enabled = true
	_draft_edit.add_theme_font_size_override("font_size", CHAT_FONT_SIZE)
	_draft_edit.add_theme_constant_override("line_spacing", CHAT_LINE_SPACING)
	_draft_edit.add_theme_color_override("font_color", Color(0.24, 0.20, 0.16, 1.0))
	_draft_edit.add_theme_color_override("font_placeholder_color", Color(0.49, 0.44, 0.36, 0.5))
	_draft_edit.add_theme_stylebox_override("normal", _make_text_edit_style(false))
	_draft_edit.add_theme_stylebox_override("focus", _make_text_edit_style(true))
	_draft_edit.text_changed.connect(_on_draft_text_changed)
	box.add_child(_draft_edit)

	var send_row := HBoxContainer.new()
	send_row.custom_minimum_size = Vector2(0.0, INPUT_SEND_ROW_HEIGHT)
	send_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(send_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_row.add_child(spacer)

	_send_button = Button.new()
	_send_button.name = "send_button"
	_send_button.custom_minimum_size = Vector2(INPUT_BUTTON_WIDTH, 96.0)
	_send_button.focus_mode = Control.FOCUS_NONE
	_send_button.text = tr("AI_IO_SEND")
	_send_button.add_theme_font_size_override("font_size", 42)
	_send_button.add_theme_color_override("font_color", Color(0.18, 0.30, 0.46, 1.0))
	_send_button.add_theme_color_override("font_disabled_color", Color(0.49, 0.44, 0.36, 0.55))
	_send_button.pressed.connect(_submit_draft)
	send_row.add_child(_send_button)
	_refresh_send_state()
	if _input_focused:
		call_deferred("_focus_draft_edit")
	return wrapper

func _make_entry_view(entry: Dictionary) -> PanelContainer:
	var role := String(entry.get("role", "system"))
	var text := String(entry.get("text", "")).strip_edges()
	var role_info := _role_info(role)
	var panel := _make_entry_panel(role_info["fill"])
	panel.custom_minimum_size = Vector2(0.0, PAGE_PANEL_MIN_HEIGHT)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var role_label := Label.new()
	role_label.add_theme_font_size_override("font_size", ROLE_FONT_SIZE)
	role_label.add_theme_color_override("font_color", role_info["color"])
	var role_label_text := String(role_info["label"])
	if int(entry.get("fragment_count", 1)) > 1 and int(entry.get("fragment_index", 0)) > 0:
		role_label_text += tr(ENTRY_CONTINUED_SUFFIX)
	role_label.text = role_label_text
	box.add_child(role_label)

	var text_label := Label.new()
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.add_theme_font_size_override("font_size", _entry_text_font_size(role))
	text_label.add_theme_constant_override("line_spacing", RESPONSE_LINE_SPACING)
	text_label.add_theme_color_override("font_color", Color(0.24, 0.20, 0.16, 1.0))
	text_label.text = text
	box.add_child(text_label)

	return panel

func _make_chat_pair_view(entry: Dictionary) -> PanelContainer:
	var answer_role := String(entry.get("answer_role", "chat_waiting"))
	var role_info := _role_info(answer_role)
	var panel := _make_entry_panel(role_info["fill"])
	panel.custom_minimum_size = Vector2(0.0, PAGE_PANEL_MIN_HEIGHT)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var question := String(entry.get("question", "")).strip_edges()
	if !question.is_empty():
		_add_chat_text_block(
			box,
			tr("AI_IO_ROLE_ME"),
			question,
			Color(0.52, 0.13, 0.09, 1.0),
			Color(0.24, 0.20, 0.16, 1.0)
		)

	var answer := String(entry.get("answer", "")).strip_edges()
	if answer.is_empty():
		answer = "\u2026\u2026"
	var answer_label_text := String(role_info["label"])
	if int(entry.get("fragment_count", 1)) > 1 and int(entry.get("fragment_index", 0)) > 0:
		answer_label_text += tr(ENTRY_CONTINUED_SUFFIX)
	_add_chat_text_block(
		box,
		answer_label_text,
		answer,
		role_info["color"],
		Color(0.24, 0.20, 0.16, 1.0)
	)
	return panel

func _add_chat_text_block(parent: VBoxContainer, role_label_text: String, text: String, role_color: Color, text_color: Color) -> void:
	var role_label := Label.new()
	role_label.add_theme_font_size_override("font_size", ROLE_FONT_SIZE)
	role_label.add_theme_color_override("font_color", role_color)
	role_label.text = role_label_text
	parent.add_child(role_label)

	var text_label := Label.new()
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.add_theme_font_size_override("font_size", CHAT_PAIR_FONT_SIZE)
	text_label.add_theme_constant_override("line_spacing", CHAT_LINE_SPACING)
	text_label.add_theme_color_override("font_color", text_color)
	text_label.text = text
	parent.add_child(text_label)

func _make_entry_panel(fill_color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.67, 0.58, 0.44, 0.22)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 14.0
	style.content_margin_top = 12.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_text_edit_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.99, 0.97, 0.91, 0.34 if focused else 0.18)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.18, 0.30, 0.46, 0.46) if focused else Color(0.67, 0.58, 0.44, 0.25)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 16.0
	style.content_margin_top = 14.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 14.0
	return style

func _role_info(role: String) -> Dictionary:
	match role:
		"ai_agent":
			return {
				"label": tr("AI_IO_ROLE_AI_REPLY"),
				"color": Color(0.13, 0.27, 0.50, 1.0),
				"fill": Color(0.13, 0.27, 0.50, 0.08),
			}
		"chat_ai":
			return {
				"label": tr("AI_IO_ROLE_CHAT"),
				"color": Color(0.13, 0.27, 0.50, 1.0),
				"fill": Color(0.13, 0.27, 0.50, 0.06),
			}
		"chat_error":
			return {
				"label": tr("AI_IO_ROLE_CHAT"),
				"color": Color(0.55, 0.11, 0.08, 1.0),
				"fill": Color(0.73, 0.18, 0.13, 0.06),
			}
		"chat_waiting":
			return {
				"label": tr("AI_IO_ROLE_CHAT"),
				"color": Color(0.36, 0.31, 0.24, 1.0),
				"fill": Color(0.64, 0.57, 0.45, 0.05),
			}
		"chat_user":
			return {
				"label": tr("AI_IO_ROLE_ME"),
				"color": Color(0.52, 0.13, 0.09, 1.0),
				"fill": Color(0.73, 0.18, 0.13, 0.05),
			}
		"review":
			return {
				"label": tr("AI_IO_ROLE_REVIEW"),
				"color": Color(0.25, 0.24, 0.49, 1.0),
				"fill": Color(0.25, 0.24, 0.49, 0.08),
			}
		"error":
			return {
				"label": tr("AI_IO_ROLE_ERROR"),
				"color": Color(0.55, 0.11, 0.08, 1.0),
				"fill": Color(0.73, 0.18, 0.13, 0.08),
			}
		"player":
			return {
				"label": tr("AI_IO_ROLE_PLAYER_INPUT"),
				"color": Color(0.52, 0.13, 0.09, 1.0),
				"fill": Color(0.73, 0.18, 0.13, 0.08),
			}
		"ai":
			return {
				"label": tr("AI_IO_ROLE_AI_OUTPUT"),
				"color": Color(0.13, 0.27, 0.50, 1.0),
				"fill": Color(0.13, 0.27, 0.50, 0.08),
			}
		_:
			return {
				"label": tr("AI_IO_ROLE_SYSTEM"),
				"color": Color(0.36, 0.31, 0.24, 1.0),
				"fill": Color(0.64, 0.57, 0.45, 0.08),
			}

func _entry_text_font_size(role: String) -> int:
	match role:
		"review":
			return RESPONSE_FONT_SIZE
		"error":
			return 58
		_:
			return RESPONSE_FONT_SIZE

func _submit_draft() -> void:
	_sync_draft_from_text_edit()
	var clean_text := _draft_text.strip_edges()
	if clean_text.is_empty():
		_refresh_send_state()
		_focus_draft_edit()
		return
	_chat_pages.push_back(_make_chat_pair_entry(clean_text, "chat_waiting", "\u2026\u2026"))
	_chat_fragment_cache.push_back({})
	_mark_pages_dirty()
	_draft_text = ""
	if _draft_edit != null and is_instance_valid(_draft_edit):
		_draft_edit.text = ""
	_input_focused = false
	show_latest_chat_page()
	chat_submitted.emit(clean_text)

func _make_chat_pair_entry(question: String, answer_role: String, answer: String) -> Dictionary:
	return {
		"role": "chat_pair",
		"question": question,
		"answer_role": answer_role,
		"answer": answer,
	}

func _focus_draft_edit() -> void:
	_input_focused = true
	if _draft_edit == null or !is_instance_valid(_draft_edit):
		return
	_draft_edit.grab_focus()

func _sync_draft_from_text_edit() -> void:
	if _draft_edit == null or !is_instance_valid(_draft_edit):
		return
	_draft_text = _draft_edit.text

func _on_draft_text_changed() -> void:
	_sync_draft_from_text_edit()
	_refresh_send_state()

func _refresh_send_state() -> void:
	if _send_button == null or !is_instance_valid(_send_button):
		return
	_send_button.disabled = _draft_text.strip_edges().is_empty()

func _button_contains_point(button: Button, fallback_rect: Rect2, viewport_position: Vector2) -> bool:
	if button != null and is_instance_valid(button):
		var button_rect := button.get_global_rect()
		if button_rect.size.x > 0.0 and button_rect.size.y > 0.0:
			if _grow_rect(button_rect, BUTTON_HIT_PADDING).has_point(viewport_position):
				return true
	return _grow_rect(fallback_rect, BUTTON_HIT_PADDING).has_point(viewport_position)

func _input_panel_contains_point(viewport_position: Vector2) -> bool:
	if _input_panel != null and is_instance_valid(_input_panel):
		var panel_rect := _input_panel.get_global_rect()
		if panel_rect.size.x > 0.0 and panel_rect.size.y > 0.0:
			return panel_rect.has_point(viewport_position)
	return _input_fallback_rect().has_point(viewport_position)

func _grow_rect(rect: Rect2, padding: Vector2) -> Rect2:
	return rect.grow_individual(padding.x, padding.y, padding.x, padding.y)

func _input_panel_target_size() -> Vector2:
	var view_size := _sheet_view_size()
	return Vector2(
		maxf(INPUT_PANEL_MIN_SIZE.x, view_size.x * INPUT_PANEL_SCALE.x),
		maxf(INPUT_PANEL_MIN_SIZE.y, PAGE_PANEL_MIN_HEIGHT * INPUT_PANEL_SCALE.y)
	)

func _input_draft_height(input_size: Vector2) -> float:
	var chrome_height := INPUT_SEND_ROW_HEIGHT + ENTRY_BOX_SEPARATION + ENTRY_PANEL_MARGIN_Y
	return maxf(280.0, input_size.y - chrome_height)

func _input_fallback_rect() -> Rect2:
	var view_size := _sheet_view_size()
	var input_size := _input_panel_target_size()
	return Rect2((view_size - input_size) * 0.5, input_size)

func _sheet_view_size() -> Vector2:
	if size.x > 0.0 and size.y > 0.0:
		return size
	return Vector2(1100.0, 1550.0)

func _note_page_count() -> int:
	return _note_pages().size()

func _is_input_page() -> bool:
	return String(_page_descriptor(_current_page).get("type", "")) == "input"

func _chat_page_index(page: Dictionary) -> int:
	if String(page.get("type", "")) != "chat":
		return -1
	var index := int(page.get("chat_index", -1))
	if index >= 0 and index < _chat_pages.size():
		return index
	return -1

func _chat_page_entry(page: Dictionary) -> Dictionary:
	if String(page.get("type", "")) != "chat":
		return {}
	var entry_variant: Variant = page.get("chat_entry", null)
	if entry_variant is Dictionary:
		return (entry_variant as Dictionary).duplicate(true)
	var chat_index := _chat_page_index(page)
	if chat_index < 0:
		return {}
	var raw_entry := _chat_pages[chat_index] as Dictionary
	return {} if raw_entry == null else raw_entry.duplicate(true)

func _mark_pages_dirty(invalidate_notes: bool = false, invalidate_chats: bool = false) -> void:
	_pages_dirty = true
	if invalidate_notes:
		_note_pages_dirty = true
		_note_pages_cache.clear()
	if invalidate_chats:
		_chat_fragment_cache.clear()

func _sync_layout_cache_state() -> void:
	var width := _entry_text_max_width()
	if _pages_cache_width >= 0.0 and absf(_pages_cache_width - width) <= 0.5:
		return
	_pages_cache_width = width
	_mark_pages_dirty(true, true)

func _ensure_chat_fragment_cache_size() -> void:
	while _chat_fragment_cache.size() < _chat_pages.size():
		_chat_fragment_cache.push_back({})
	while _chat_fragment_cache.size() > _chat_pages.size():
		_chat_fragment_cache.pop_back()

func _invalidate_chat_fragment(chat_index: int) -> void:
	if chat_index < 0:
		return
	_ensure_chat_fragment_cache_size()
	if chat_index < _chat_fragment_cache.size():
		_chat_fragment_cache[chat_index] = {}

func _page_descriptor(page_index: int) -> Dictionary:
	var pages := _page_descriptors()
	if pages.is_empty():
		return {"type": "cover"}
	return pages[clampi(page_index, 0, pages.size() - 1)] as Dictionary

func _page_descriptors() -> Array:
	_sync_layout_cache_state()
	if !_pages_dirty:
		return _pages_cache

	var pages: Array = []
	if _entries.is_empty() and _chat_pages.is_empty():
		pages.push_back({"type": "cover"})
		pages.push_back({"type": "input"})
		_pages_cache = pages
		_pages_dirty = false
		return _pages_cache

	var note_pages := _note_pages()
	var note_slot := clampi(_note_after_chat_count, 0, _chat_pages.size())
	for slot: int in range(_chat_pages.size() + 1):
		if !note_pages.is_empty() and slot == note_slot:
			for note_page in note_pages:
				pages.push_back({
					"type": "note",
					"entries": note_page,
				})
		pages.push_back({"type": "input"})
		if slot < _chat_pages.size():
			var chat_entry := _chat_pages[slot] as Dictionary
			if chat_entry == null:
				continue
			for chat_fragment_variant in _split_chat_pair_fragments(chat_entry, slot):
				var chat_fragment := chat_fragment_variant as Dictionary
				if chat_fragment == null:
					continue
				pages.push_back({
					"type": "chat",
					"chat_index": slot,
					"chat_entry": chat_fragment,
				})
	_pages_cache = pages
	_pages_dirty = false
	return _pages_cache

func _note_pages() -> Array:
	if !_note_pages_dirty:
		return _note_pages_cache
	if _entries.is_empty():
		_note_pages_cache = []
		_note_pages_dirty = false
		return _note_pages_cache
	var expanded_entries: Array = []
	for entry_variant in _entries:
		var entry := entry_variant as Dictionary
		if entry == null:
			continue
		expanded_entries.append_array(_split_entry_fragments(entry))
	if expanded_entries.is_empty():
		_note_pages_cache = []
		_note_pages_dirty = false
		return _note_pages_cache
	var pages: Array = []
	for start_index: int in range(0, expanded_entries.size(), max_entries_per_page):
		pages.push_back(expanded_entries.slice(start_index, mini(start_index + max_entries_per_page, expanded_entries.size())))
	_note_pages_cache = pages
	_note_pages_dirty = false
	return _note_pages_cache

func _split_entry_fragments(entry: Dictionary) -> Array:
	var role := String(entry.get("role", "system"))
	var text := String(entry.get("text", "")).strip_edges()
	if text.is_empty():
		return [entry.duplicate(true)]

	var fragments := _split_text_across_pages(text, role)
	if fragments.size() <= 1:
		var single_entry := entry.duplicate(true)
		single_entry["fragment_index"] = 0
		single_entry["fragment_count"] = 1
		return [single_entry]

	var result: Array = []
	for fragment_index: int in range(fragments.size()):
		var fragment_entry := entry.duplicate(true)
		fragment_entry["text"] = String(fragments[fragment_index])
		fragment_entry["fragment_index"] = fragment_index
		fragment_entry["fragment_count"] = fragments.size()
		result.push_back(fragment_entry)
	return result

func _split_chat_pair_fragments(entry: Dictionary, chat_index: int = -1) -> Array:
	if chat_index >= 0:
		_ensure_chat_fragment_cache_size()
		var signature := JSON.stringify(entry)
		var width := _entry_text_max_width()
		var cached := _chat_fragment_cache[chat_index] as Dictionary
		if cached != null \
				and String(cached.get("signature", "")) == signature \
				and absf(float(cached.get("width", -1.0)) - width) <= 0.5:
			var cached_fragments := cached.get("fragments", []) as Array
			return cached_fragments if cached_fragments != null else []
		var fragments := _build_chat_pair_fragments(entry)
		_chat_fragment_cache[chat_index] = {
			"signature": signature,
			"width": width,
			"fragments": fragments,
		}
		return fragments
	return _build_chat_pair_fragments(entry)

func _build_chat_pair_fragments(entry: Dictionary) -> Array:
	var question := String(entry.get("question", "")).strip_edges()
	var answer := String(entry.get("answer", "")).strip_edges()
	if answer.is_empty():
		answer = "\u2026\u2026"

	var font := _entry_layout_font()
	if font == null:
		return _split_chat_pair_by_character_budget(entry, question, answer)

	var max_width := _entry_text_max_width()
	var answer_lines := _wrap_text_lines(answer, font, max_width, CHAT_PAIR_FONT_SIZE)
	var question_line_count := 0
	if !question.is_empty():
		question_line_count = _wrap_text_lines(question, font, max_width, CHAT_PAIR_FONT_SIZE).size()

	var result: Array = []
	var answer_line_index := 0
	while answer_line_index < answer_lines.size():
		var is_first_fragment := result.is_empty()
		var max_lines := _chat_answer_max_lines(
			question_line_count if is_first_fragment else 0,
			font,
			is_first_fragment and !question.is_empty()
		)
		var end_index := mini(answer_line_index + max_lines, answer_lines.size())
		if end_index <= answer_line_index:
			end_index = answer_line_index + 1
		var fragment_entry := entry.duplicate(true)
		fragment_entry["question"] = question if is_first_fragment else ""
		fragment_entry["answer"] = "\n".join(answer_lines.slice(answer_line_index, end_index)).strip_edges()
		fragment_entry["fragment_index"] = result.size()
		result.push_back(fragment_entry)
		answer_line_index = end_index

	if result.is_empty():
		var fallback_entry := entry.duplicate(true)
		fallback_entry["question"] = question
		fallback_entry["answer"] = answer
		fallback_entry["fragment_index"] = 0
		result.push_back(fallback_entry)

	var fragment_count := result.size()
	for index: int in range(result.size()):
		var fragment := result[index] as Dictionary
		if fragment != null:
			fragment["fragment_count"] = fragment_count
	return result

func _split_chat_pair_by_character_budget(entry: Dictionary, question: String, answer: String) -> Array:
	var answer_fragments := _split_text_by_character_budget(answer)
	var result: Array = []
	for fragment_index: int in range(answer_fragments.size()):
		var fragment_entry := entry.duplicate(true)
		fragment_entry["question"] = question if fragment_index == 0 else ""
		fragment_entry["answer"] = String(answer_fragments[fragment_index])
		fragment_entry["fragment_index"] = fragment_index
		fragment_entry["fragment_count"] = answer_fragments.size()
		result.push_back(fragment_entry)
	return result

func _split_text_across_pages(text: String, role: String) -> Array:
	var normalized_text := text.replace("\r\n", "\n").replace("\r", "\n")
	if normalized_text.is_empty():
		return [""]

	var font := _entry_layout_font()
	if font == null:
		return _split_text_by_character_budget(normalized_text)

	var max_width := _entry_text_max_width()
	var max_lines := _entry_max_lines(role, font)
	var pages: Array[String] = []
	var page_lines: Array[String] = []
	var current_line := ""

	for character in normalized_text:
		if character == "\n":
			_push_line_to_pages(current_line, page_lines, pages, max_lines)
			current_line = ""
			continue

		var next_line := current_line + character
		if current_line.is_empty() or _measure_line_width(font, next_line, _entry_text_font_size(role)) <= max_width:
			current_line = next_line
			continue

		_push_line_to_pages(current_line, page_lines, pages, max_lines)
		current_line = character

	_push_line_to_pages(current_line, page_lines, pages, max_lines)
	_flush_page_lines(page_lines, pages)

	if pages.is_empty():
		pages.push_back(normalized_text)
	return pages

func _wrap_text_lines(text: String, font: Font, max_width: float, font_size: int) -> Array:
	var normalized_text := text.replace("\r\n", "\n").replace("\r", "\n")
	if normalized_text.is_empty():
		return [""]

	var lines: Array = []
	var current_line := ""
	for character in normalized_text:
		if character == "\n":
			lines.push_back(current_line)
			current_line = ""
			continue

		var next_line := current_line + character
		if current_line.is_empty() or _measure_line_width(font, next_line, font_size) <= max_width:
			current_line = next_line
			continue

		lines.push_back(current_line)
		current_line = character

	lines.push_back(current_line)
	return lines

func _split_text_by_character_budget(text: String) -> Array:
	var fragments: Array[String] = []
	var character_budget := 220
	for start_index: int in range(0, text.length(), character_budget):
		fragments.push_back(text.substr(start_index, character_budget))
	if fragments.is_empty():
		fragments.push_back(text)
	return fragments

func _push_line_to_pages(line: String, page_lines: Array[String], pages: Array[String], max_lines: int) -> void:
	if page_lines.size() >= max_lines:
		_flush_page_lines(page_lines, pages)
	page_lines.push_back(line)

func _flush_page_lines(page_lines: Array[String], pages: Array[String]) -> void:
	if page_lines.is_empty():
		return
	pages.push_back("\n".join(page_lines).strip_edges())
	page_lines.clear()

func _entry_layout_font() -> Font:
	var default_font := get_theme_default_font()
	if default_font != null:
		return default_font
	return ThemeDB.fallback_font

func _entry_text_max_width() -> float:
	var available_width := rows_container.size.x - ENTRY_PANEL_MARGIN_X
	if available_width > 0.0:
		return available_width
	return ENTRY_TEXT_WIDTH_FALLBACK

func _entry_max_lines(role: String, font: Font) -> int:
	var role_font_height := font.get_height(ROLE_FONT_SIZE)
	var line_height := font.get_height(_entry_text_font_size(role)) + RESPONSE_LINE_SPACING
	var available_height := PAGE_PANEL_MIN_HEIGHT - ENTRY_PANEL_MARGIN_Y - ENTRY_BOX_SEPARATION - role_font_height - ENTRY_TEXT_HEIGHT_SAFETY
	return maxi(1, int(floor((available_height + RESPONSE_LINE_SPACING) / line_height)))

func _chat_answer_max_lines(question_line_count: int, font: Font, includes_question: bool) -> int:
	var role_font_height := font.get_height(ROLE_FONT_SIZE)
	var line_height := font.get_height(CHAT_PAIR_FONT_SIZE) + CHAT_LINE_SPACING
	var label_count := 1 + (1 if includes_question else 0)
	var text_block_count := 1 + (1 if includes_question else 0)
	var separation_count := maxi(0, label_count + text_block_count - 1)
	var question_text_height := float(question_line_count) * line_height
	var available_height := PAGE_PANEL_MIN_HEIGHT - ENTRY_PANEL_MARGIN_Y - ENTRY_TEXT_HEIGHT_SAFETY
	available_height -= float(label_count) * role_font_height
	available_height -= question_text_height
	available_height -= float(separation_count) * ENTRY_BOX_SEPARATION
	return maxi(1, int(floor((available_height + CHAT_LINE_SPACING) / line_height)))

func _measure_line_width(font: Font, text: String, font_size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x

func _find_note_page_index() -> int:
	var pages := _page_descriptors()
	for index: int in range(pages.size()):
		var page := pages[index] as Dictionary
		if page != null and String(page.get("type", "")) == "note":
			return index
	return -1

func _find_latest_note_page_index() -> int:
	var pages := _page_descriptors()
	var found_index := -1
	for index: int in range(pages.size()):
		var page := pages[index] as Dictionary
		if page != null and String(page.get("type", "")) == "note":
			found_index = index
	return found_index

func _find_chat_page_index(chat_index: int) -> int:
	var pages := _page_descriptors()
	for index: int in range(pages.size()):
		var page := pages[index] as Dictionary
		if page == null or String(page.get("type", "")) != "chat":
			continue
		if int(page.get("chat_index", -1)) == chat_index:
			return index
	return -1
