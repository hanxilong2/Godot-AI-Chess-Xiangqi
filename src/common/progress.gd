extends Node

# 全局存档系统
# 由于Archive名称已占用，故命名Progress，也就是游玩进展
# 这里的存档区分于Archive，Archive是允许跨越多个存档的文件机制

var table:Dictionary = {}

const PROGRESS_FILE_PATH:String = "user://progress/prototype_2.json"
const PROGRESS_DIR_PATH:String = "user://progress"

func _ready() -> void:
	load_file()

func load_file() -> void:
	var file:FileAccess = FileAccess.open(PROGRESS_FILE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed:Variant = JSON.parse_string(file.get_as_text())
	file.close()
	table = parsed if parsed is Dictionary else {}

func save_file() -> void:
	var dir:DirAccess = DirAccess.open(PROGRESS_DIR_PATH)
	if !dir:
		DirAccess.make_dir_absolute(PROGRESS_DIR_PATH)
		dir = DirAccess.open(PROGRESS_DIR_PATH)
	if dir == null:
		return
	var file:FileAccess = FileAccess.open(PROGRESS_FILE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(table))
	file.close()

func has_key(key:String) -> bool:
	return table.has(key)

func get_value(key:String, default:Variant = null) -> Variant:
	if table.has(key):
		return table[key]
	return default

func set_value(key:String, data:Variant) -> void:
	table[key] = data

func accumulate(key:String, data:Variant) -> void:
	if !table.has(key):
		table[key] = data
	table[key] += data

func create_if_not_exist(key:String, data:Variant) -> void:
	if !has_key(key):
		table[key] = data

func clear() -> void:
	if FileAccess.file_exists(PROGRESS_FILE_PATH):
		DirAccess.remove_absolute(PROGRESS_FILE_PATH)
	table = {}
