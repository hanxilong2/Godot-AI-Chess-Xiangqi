extends Control
class_name XiangqiMoveSheet

@export var title_text := "\u843d\u5b50\u8bb0\u5f55"
@export var max_info_lines := 10

var _entries: Array = []
var _current_page := 0

@onready var title_label: Label = $margin/frame/v_box/title_label
@onready var subtitle_label: Label = $margin/frame/v_box/subtitle_label
@onready var separator: HSeparator = $margin/frame/v_box/separator
@onready var rows_container: VBoxContainer = $margin/frame/v_box/rows_container

func _ready() -> void:
	_refresh()

func set_title_text(value: String) -> void:
	title_text = value
	if is_node_ready():
		title_label.text = title_text

func set_entries(entries: Array) -> void:
	_entries = entries.duplicate(true)
	show_latest_page()

func clear_entries() -> void:
	set_entries([])

func set_current_page(page_index: int) -> void:
	_current_page = clampi(page_index, 0, get_page_count() - 1)
	if is_node_ready():
		_refresh_rows()

func show_latest_page() -> void:
	_current_page = get_page_count() - 1
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
	return maxi(1, int(ceil(float(get_move_count()) / float(max_info_lines))))

func get_current_page() -> int:
	return _current_page

func get_move_count() -> int:
	return get_notation_lines().size()

func get_visible_entries() -> Array:
	return get_visible_notation_lines()

func get_notation_lines() -> Array:
	var lines: Array = []
	for row_variant in _entries:
		var row := row_variant as Dictionary
		if row == null:
			continue
		var red_move := String(row.get("red", "")).strip_edges()
		var black_move := String(row.get("black", "")).strip_edges()
		if !red_move.is_empty():
			lines.push_back({
				"side": "\u7ea2",
				"move": red_move,
			})
		if !black_move.is_empty():
			lines.push_back({
				"side": "\u9ed1",
				"move": black_move,
			})
	return lines

func get_visible_notation_lines() -> Array:
	var lines := get_notation_lines()
	if lines.is_empty():
		return []
	var start_index := _current_page * max_info_lines
	var end_index := mini(start_index + max_info_lines, lines.size())
	return lines.slice(start_index, end_index)

func _refresh() -> void:
	title_label.text = title_text
	subtitle_label.text = ""
	subtitle_label.visible = false
	separator.visible = false
	_refresh_rows()

func _refresh_rows() -> void:
	for child in rows_container.get_children():
		child.queue_free()

	if _entries.is_empty():
		var empty_panel := _make_row_panel(Color(0.79, 0.73, 0.63, 0.10))
		var empty_label := Label.new()
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_label.custom_minimum_size = Vector2(0.0, 520.0)
		empty_label.add_theme_font_size_override("font_size", 30)
		empty_label.add_theme_color_override("font_color", Color(0.35, 0.31, 0.26, 1.0))
		empty_label.text = "\u843d\u5b50\u540e\uff0c\u8bb0\u5f55\u4f1a\u5199\u5728\u8fd9\u91cc\u3002"
		empty_panel.add_child(empty_label)
		rows_container.add_child(empty_panel)
		return

	for line_index: int in range(get_visible_notation_lines().size()):
		var line_data := get_visible_notation_lines()[line_index] as Dictionary
		var tone := 0.065 if line_index % 2 == 0 else 0.035
		var row_panel := _make_row_panel(Color(0.64, 0.57, 0.45, tone), 10.0)
		var side_text := String(line_data.get("side", "")).strip_edges()
		var move_text := String(line_data.get("move", "")).strip_edges()
		var move_color := Color(0.55, 0.15, 0.10, 1.0) if side_text == "\u7ea2" else Color(0.12, 0.12, 0.12, 1.0)
		row_panel.add_child(_make_side_line(side_text, move_text, move_color))
		rows_container.add_child(row_panel)

func _make_row_panel(fill_color: Color, corner_radius: float = 8.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.67, 0.58, 0.44, 0.22)
	style.corner_radius_top_left = int(corner_radius)
	style.corner_radius_top_right = int(corner_radius)
	style.corner_radius_bottom_right = int(corner_radius)
	style.corner_radius_bottom_left = int(corner_radius)
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_side_line(side_text: String, move_text: String, color: Color) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 10)

	var side_label := Label.new()
	side_label.custom_minimum_size = Vector2(42.0, 70.0)
	side_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	side_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	side_label.add_theme_font_size_override("font_size", 60)
	side_label.add_theme_color_override("font_color", color)
	side_label.text = side_text
	line.add_child(side_label)

	var move_label := Label.new()
	move_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_label.custom_minimum_size = Vector2(0.0, 64.0)
	move_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	move_label.add_theme_font_size_override("font_size", 60)
	move_label.add_theme_color_override("font_color", color)
	move_label.text = move_text
	line.add_child(move_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(42.0, 64.0)
	line.add_child(spacer)

	return line
