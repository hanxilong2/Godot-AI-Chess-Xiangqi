extends Notable

@export var img_path:String = ""

func _ready() -> void:
	_load_image_texture()

func parse(data:Dictionary) -> void:
	super.parse(data)
	img_path = String(data.get("path", ""))
	_load_image_texture()

func _load_image_texture() -> void:
	if img_path.is_empty():
		$sprite_2d.texture = null
		return
	if ResourceLoader.exists(img_path):
		$sprite_2d.texture = load(img_path)
	else:
		var image:Image = Image.load_from_file(img_path)
		$sprite_2d.texture = ImageTexture.create_from_image(image) if !image.is_empty() else null

func dict() -> Dictionary:
	var data:Dictionary = super.dict()
	data["path"] = img_path
	return data

func get_rect() -> Rect2:
	return $sprite_2d.get_rect() * $sprite_2d.transform
