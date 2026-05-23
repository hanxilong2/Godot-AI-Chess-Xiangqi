extends Notable

class HistoryPage extends RefCounted:
	var state:State = null
	var history:PackedStringArray = []

var page_list:Array[HistoryPage] = []
var current_page:int = 0
var current_page_instance:HistoryPage = null

func parse(data:Dictionary) -> void:
	super.parse(data)
	page_list.clear()
	var data_arr:Variant = data.get("history", [])
	if data_arr is Array:
		for iter:Variant in data_arr:
			if !(iter is Dictionary):
				continue
			var page:HistoryPage = HistoryPage.new()
			var fen:String = String(iter.get("state", ""))
			page.state = Chess.parse(fen) if !fen.is_empty() else Chess.create_initial_state()
			if page.state == null:
				page.state = Chess.create_initial_state()
			page.history = _history_to_packed_string_array(iter.get("history", []))
			page_list.push_back(page)
	if page_list.is_empty():
		var page:HistoryPage = HistoryPage.new()
		page.state = Chess.create_initial_state()
		page_list.push_back(page)
	current_page = 0
	current_page_instance = page_list[current_page]
	update_table()

func dict() -> Dictionary:
	var data:Dictionary = super.dict()
	var data_arr:Array = []
	for page:HistoryPage in page_list:
		var iter:Dictionary = {}
		var state:State = page.state if page.state != null else Chess.create_initial_state()
		var fen:String = Chess.stringify(state)
		iter["state"] = fen
		iter["history"] = page.history
		data_arr.push_back(iter)
	data["history"] = data_arr
	return data

func get_rect() -> Rect2:
	return $history.get_rect() * $history.transform

func set_state(_state:State) -> void:
	if current_page_instance == null:
		new_page()
	current_page_instance.state = _state.duplicate()
	current_page_instance.history.clear()
	update_table()

func push_move(move:int) -> void:
	if current_page_instance == null or current_page_instance.state == null:
		return
	if current_page_instance.history.size() >= 120:
		return
	current_page_instance.history.push_back(Chess.get_move_name(current_page_instance.state, move))
	Chess.apply_move(current_page_instance.state, move)
	update_table()

func rollback(_state:State, pop_count:int = 1) -> void:
	if current_page_instance == null:
		return
	current_page_instance.history.resize(maxi(0, current_page_instance.history.size() - pop_count))
	current_page_instance.state = _state.duplicate()
	update_table()

func update_table() -> void:
	if current_page_instance == null:
		return
	for i:int in range(60):
		var white_label := get_node_or_null("white/label_%d" % (i + 1)) as Label
		var black_label := get_node_or_null("black/label_%d" % (i + 1)) as Label
		if white_label != null:
			white_label.text = ""
		if black_label != null:
			black_label.text = ""
	if current_page_instance.state == null:
		return
	$chessboard_flat.set_state(current_page_instance.state)
	for i:int in range(current_page_instance.history.size()):
		if i % 2 == 0:
			var white_label := get_node_or_null("white/label_%d" % (i / 2 + 1)) as Label
			if white_label != null:
				white_label.text = current_page_instance.history[i]
		else:
			var black_label := get_node_or_null("black/label_%d" % (i / 2 + 1)) as Label
			if black_label != null:
				black_label.text = current_page_instance.history[i]

func add_blank_line() -> void:
	if current_page_instance == null:
		return
	current_page_instance.history.push_back("")
	current_page_instance.history.push_back("")

func new_page() -> void:
	super.new_page()
	var page:HistoryPage = HistoryPage.new()
	page.state = Chess.create_initial_state()
	page_list.push_back(page)
	current_page = page_list.size() - 1
	current_page_instance = page

func turn_page(_page:int) -> void:
	super.turn_page(_page)
	if page_list.is_empty():
		new_page()
		return
	_page = clampi(_page, 0, page_list.size() - 1)
	current_page = _page
	current_page_instance = page_list[current_page]
	update_table()

func page_count() -> int:
	return page_list.size()

func page_index() -> int:
	return current_page

func _history_to_packed_string_array(value:Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var output := PackedStringArray()
	if value is Array:
		for iter:Variant in value:
			output.push_back(String(iter))
	return output
