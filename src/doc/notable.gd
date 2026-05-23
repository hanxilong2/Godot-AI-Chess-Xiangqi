extends Document
class_name Notable

var lines:Array[Line2D] = [] # 线条
var drawing_line:Line2D = null
var width:float = 3
var color:Color = Color(0.1, 0.1, 0.1, 1)

class NotablePage extends RefCounted:
	var lines:Array = []

var notable_page_list:Array[NotablePage] = []
var _notable_current_page:int = 0

func parse(data:Dictionary) -> void:
	clear_lines()
	notable_page_list.clear()
	_notable_current_page = 0
	var data_arr:Variant = data.get("notable", [])
	if data_arr is Array:
		for iter:Variant in data_arr:
			var page:NotablePage = NotablePage.new()
			if iter is Dictionary:
				page.lines = _normalize_line_list(iter.get("lines", []))
			notable_page_list.push_back(page)
	_ensure_notable_page()
	draw_lines(notable_page_list[_notable_current_page].lines)

func dict() -> Dictionary:
	_ensure_notable_page()
	notable_page_list[_notable_current_page].lines = get_lines()
	var data:Dictionary = {}
	var data_arr:Array = []
	for page:NotablePage in notable_page_list:
		var iter:Dictionary = {}
		iter["lines"] = page.lines
		data_arr.push_back(iter)
	data["notable"] = data_arr
	return data

func get_rect() -> Rect2:
	return Rect2(-552 / 2, -780 / 2, 552, 780)

func click(_click_position:Vector2) -> void:
	pass

func start_dragging(start_position:Vector2) -> void:
	var new_line:Line2D = Line2D.new()
	new_line.joint_mode = Line2D.LINE_JOINT_ROUND
	new_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	new_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	new_line.default_color = color
	new_line.width = width
	new_line.add_point(start_position)
	drawing_line = new_line
	add_child(new_line)
	lines.push_back(new_line)

func dragging(drawing_position:Vector2) -> void:
	if !is_instance_valid(drawing_line):
#		start_draw(finger_index, drawing_position)
		return
	if drawing_line.get_point_count() > 0 && drawing_line.get_point_position(drawing_line.get_point_count() - 1).distance_squared_to(drawing_position) < 3 * 3:
		return
	drawing_line.add_point(drawing_position)

func drawing_straight(drawing_position) -> void:
	if !is_instance_valid(drawing_line):
		return
	#if drawing_line.get_point_count() > 0 && drawing_line.get_point_position(drawing_line.get_point_count() - 1).distance_squared_to(drawing_position) < 3 * 3:
	#	return
	# 有可能会做折现，不做清理
	if drawing_line.get_point_count() < 2:
		drawing_line.add_point(drawing_position)
	drawing_line.set_point_position(drawing_line.get_point_count() - 1, drawing_position)

func end_dragging() -> void:
	if !is_instance_valid(drawing_line):
		return
	drawing_line = null

func cancel_dragging() -> void:
	if is_instance_valid(drawing_line):
		if lines.has(drawing_line):
			lines.erase(drawing_line)
		drawing_line.queue_free()

func erase(drawing_position:Vector2) -> void:
	cancel_dragging()
	var point_list:Array = lines.duplicate(false)
	for iter:Line2D in point_list:
		if iter.get_point_count() < 2:
			lines.erase(iter)
			iter.queue_free()
		for i:int in iter.get_point_count():
			if iter.get_point_position(i).distance_squared_to(drawing_position) < 10 * 10:
				lines.erase(iter)
				iter.queue_free()
				break

func clear_lines() -> void:
	for iter:Line2D in lines:
		iter.queue_free()
	lines.clear()

func get_lines() -> Array:
	var output:Array = []
	for iter:Line2D in lines:
		var point_list:PackedFloat32Array = []
		for i:int in iter.get_point_count():
			point_list.push_back(iter.get_point_position(i).x)
			point_list.push_back(iter.get_point_position(i).y)
		output.push_back(point_list)
	return output

func draw_lines(_lines:Array) -> void:
	for iter:Variant in _lines:
		var point_values:PackedFloat32Array = _line_to_packed_array(iter)
		var line:Line2D = Line2D.new()
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.default_color = color
		line.width = width
		for i:int in range(point_values.size() / 2):
			var point:Vector2 = Vector2(point_values[i * 2], point_values[i * 2 + 1])
			line.add_point(point)
		add_child(line)
		lines.push_back(line)

func new_page() -> void:
	if !notable_page_list.is_empty():
		notable_page_list[_notable_current_page].lines = get_lines()
	clear_lines()
	var page:NotablePage = NotablePage.new()
	notable_page_list.push_back(page)
	_notable_current_page = notable_page_list.size() - 1

func turn_page(_page:int) -> void:
	_ensure_notable_page()
	_page = clampi(_page, 0, notable_page_list.size() - 1)
	notable_page_list[_notable_current_page].lines = get_lines()
	clear_lines()
	_notable_current_page = _page
	draw_lines(notable_page_list[_page].lines)

func page_count() -> int:
	_ensure_notable_page()
	return notable_page_list.size()

func page_index() -> int:
	return _notable_current_page

func _ensure_notable_page() -> void:
	if notable_page_list.is_empty():
		notable_page_list.push_back(NotablePage.new())
	_notable_current_page = clampi(_notable_current_page, 0, notable_page_list.size() - 1)

func _normalize_line_list(line_list:Variant) -> Array:
	var output:Array = []
	if !(line_list is Array):
		return output
	for line_data:Variant in line_list:
		var point_values:PackedFloat32Array = _line_to_packed_array(line_data)
		if point_values.size() >= 2:
			output.push_back(point_values)
	return output

func _line_to_packed_array(line_data:Variant) -> PackedFloat32Array:
	if line_data is PackedFloat32Array:
		return line_data
	var point_values := PackedFloat32Array()
	if line_data is Array:
		for value:Variant in line_data:
			point_values.push_back(float(value))
	return point_values
