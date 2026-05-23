extends Document
class_name Model

var model_path:String = ""
var model_instance:Node3D = null

var last_position:Vector2 = Vector2(0, 0)

func parse(data:Dictionary) -> void:
	set_model(String(data.get("path", "")))

func dict() -> Dictionary:
	var data:Dictionary = {}
	data["path"] = model_path
	return data

func set_model(_model_path:String) -> void:
	if is_instance_valid(model_instance):
		model_instance.queue_free()
	model_path = _model_path
	if model_path.is_empty() or !ResourceLoader.exists(model_path):
		model_instance = null
		return
	var model_scene := load(model_path) as PackedScene
	if model_scene == null:
		model_instance = null
		return
	model_instance = model_scene.instantiate()
	$sub_viewport.add_child(model_instance)

func start_dragging(_start_position:Vector2) -> void:
	last_position = _start_position

func dragging(_drawing_position:Vector2) -> void:
	if model_instance == null:
		return
	model_instance.rotation.y += (_drawing_position.x - last_position.x) / 300
	last_position = _drawing_position
