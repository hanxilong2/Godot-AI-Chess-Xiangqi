extends CanvasLayer

var current:Node = null

func _ready() -> void:
	current = get_tree().current_scene
	get_tree().root.tree_exiting.connect(_clear_current_reference, CONNECT_ONE_SHOT)
	$texture_rect.modulate = Color(1, 1, 1, 0)
	$texture_rect.visible = false

func _clear_current_reference() -> void:
	current = null

func change_scene(path:String, meta:Dictionary, wait_time:float = 0.3) -> void:
	var packed_scene:PackedScene = _load_scene_resource(path)
	if packed_scene == null:
		return
	Progress.set_value("current_level", path)
	Progress.save_file()
	var tween:Tween = create_tween()
	tween.tween_property($texture_rect, "visible", true, 0)
	tween.tween_property($texture_rect, "modulate", Color(1, 1, 1, 1), wait_time)
	await tween.finished
	var instance:Node = packed_scene.instantiate()
	if instance == null:
		push_error("Failed to instantiate scene: %s" % path)
		_fade_out(wait_time)
		return
	for key:String in meta:
		instance.set_meta(key, meta[key])
	if is_instance_valid(current):
		current.queue_free()
	get_tree().root.add_child(instance)
	current = instance
	tween.kill()
	_fade_out(wait_time)

func _load_scene_resource(path:String) -> PackedScene:
	if path.is_empty():
		push_error("Cannot change scene: path is empty.")
		return null
	if !ResourceLoader.exists(path, "PackedScene"):
		push_error("Cannot change scene: scene does not exist: %s" % path)
		return null
	var packed_scene:PackedScene = ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed_scene == null:
		push_error("Cannot change scene: resource is not a PackedScene: %s" % path)
	return packed_scene

func _fade_out(wait_time:float) -> void:
	var tween:Tween = create_tween()
	tween.tween_property($texture_rect, "modulate", Color(1, 1, 1, 0), wait_time)
	tween.tween_property($texture_rect, "visible", false, 0)
