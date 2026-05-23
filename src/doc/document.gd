extends Node2D
class_name Document
# 文档分为模板和实例
# 实例包含了文件名称和变量

var filename:String = ""	# 文档名称，唯一
var template:String = ""	# 模板路径
const ARCHIVE_DIR_PATH:String = "user://archive"

func _ready() -> void:
	pass

func parse(_data:Dictionary) -> void:
	pass

func dict() -> Dictionary:
	return {}

func save_file() -> void:
	if filename.is_empty():
		return
	var data:String = JSON.stringify(dict())
	var path:String = _archive_file_path()
	DirAccess.make_dir_absolute(ARCHIVE_DIR_PATH)
	var file:FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(data)
	file.close()

func load_file() -> void:
	if filename.is_empty():
		return
	var path:String = _archive_file_path()
	if FileAccess.file_exists(path):
		var data:String = FileAccess.get_file_as_string(path)
		var parsed:Variant = JSON.parse_string(data)
		parse(parsed if parsed is Dictionary else {})

func clear_file() -> void:
	if filename.is_empty():
		return
	var path:String = _archive_file_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func set_filename(_filename:String) -> void:
	filename = _filename

func get_filename() -> String:
	return filename

func get_rect() -> Rect2:
	return Rect2(-552 / 2, -780 / 2, 552, 780)

func click(_click_position:Vector2) -> void:
	pass

func start_dragging(_start_position:Vector2) -> void:
	pass

func dragging(_drawing_position:Vector2) -> void:
	pass

func end_dragging() -> void:
	pass

func cancel_dragging() -> void:
	pass

func erase(_drawing_position:Vector2) -> void:
	pass

func new_page() -> void:
	pass

func turn_page(_page:int) -> void:
	pass

func page_count() -> int:
	return 0

func page_index() -> int:
	return 0

func _archive_file_path() -> String:
	return ARCHIVE_DIR_PATH.path_join(filename)
