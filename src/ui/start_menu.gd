extends Control

const CHESS_SCENE_PATH := "res://resource/chess/scene/game/chess_cafe.tscn"
const XIANGQI_SCENE_PATH := "res://resource/xiangqi/scene/game/xiangqi_cafe_game.tscn"

@onready var chess_button: Button = %chess_button
@onready var xiangqi_button: Button = %xiangqi_button
@onready var settings_button: Button = %settings_button

func _ready() -> void:
	chess_button.pressed.connect(_load_level.bind(CHESS_SCENE_PATH))
	xiangqi_button.pressed.connect(_load_level.bind(XIANGQI_SCENE_PATH))
	settings_button.pressed.connect(_open_settings)
	chess_button.grab_focus()

func _load_level(scene_path: String) -> void:
	chess_button.disabled = true
	xiangqi_button.disabled = true
	settings_button.disabled = true
	if !is_instance_valid(Loading.current):
		Loading.current = get_tree().current_scene if get_tree().current_scene != null else self
	await Loading.change_scene(scene_path, {})

func _open_settings() -> void:
	Setting.open()
