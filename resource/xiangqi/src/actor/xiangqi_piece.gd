extends Actor
class_name XiangqiPiece

const PieceLibrary := preload("res://resource/xiangqi/src/xiangqi_piece_library.gd")
const MOVE_SFX_PATH := "res://assets/audio/351518__mh2o__chess_move_on_alabaster.wav"

@export var piece_symbol: String = ""
@export var use_billboard_text: bool = true
@export var ready_lift_height: float = 0.1

const FALLBACK_LABELS := {
	"K": "帅",
	"A": "仕",
	"E": "相",
	"H": "马",
	"R": "车",
	"C": "炮",
	"P": "兵",
	"k": "将",
	"a": "士",
	"e": "象",
	"h": "马",
	"r": "车",
	"c": "炮",
	"p": "卒",
}

var _uses_model_visual := false
var _is_ready_to_move := false
var _move_sfx: AudioStreamPlayer3D = null

func _ready() -> void:
	super._ready()
	_ensure_move_sfx()
	_apply_piece_look()

func setup(symbol: String) -> XiangqiPiece:
	piece_symbol = XiangqiConstants.normalize_piece(symbol)
	if is_node_ready():
		_apply_piece_look()
	return self

func uses_model_visual() -> bool:
	return _uses_model_visual

func get_visual_mesh_count() -> int:
	var visual := get_node_or_null("piece/visual") as Node3D
	if visual == null:
		return 0
	return visual.find_children("*", "MeshInstance3D", true, false).size()

func ready_to_move() -> void:
	if _is_ready_to_move:
		return
	_is_ready_to_move = true
	global_position += Vector3(0.0, ready_lift_height, 0.0)

func idle() -> void:
	if !_is_ready_to_move:
		return
	_is_ready_to_move = false
	global_position -= Vector3(0.0, ready_lift_height, 0.0)

func move(_pos: Vector3) -> void:
	var tween := create_tween()
	tween.tween_callback(_play_move_sfx)
	tween.tween_property(self, "global_position", _pos, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(animation_finished.emit)

func capturing(_pos: Vector3, _captured: Actor) -> void:
	var tween := create_tween()
	tween.tween_callback(_play_move_sfx)
	tween.tween_property(self, "global_position", _pos, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(animation_finished.emit)
	_captured.captured(self)

func _apply_piece_look() -> void:
	var body := get_node_or_null("piece/body") as MeshInstance3D
	var letter := get_node_or_null("piece/letter") as Label3D
	var visual := get_node_or_null("piece/visual") as Node3D
	_clear_visual(visual)
	_uses_model_visual = false

	if visual != null:
		var model_visual: Node3D = PieceLibrary.instantiate_visual(piece_symbol)
		if model_visual != null:
			visual.add_child(model_visual)
			_uses_model_visual = true

	if body != null:
		body.visible = !_uses_model_visual
		var material := StandardMaterial3D.new()
		material.roughness = 0.88
		if XiangqiConstants.side_from_piece(piece_symbol) == XiangqiConstants.RED:
			material.albedo_color = Color(0.87, 0.80, 0.67, 1.0)
			if letter != null:
				letter.modulate = Color(0.60, 0.10, 0.08, 1.0)
		else:
			material.albedo_color = Color(0.19, 0.19, 0.19, 1.0)
			if letter != null:
				letter.modulate = Color(0.92, 0.88, 0.76, 1.0)
		body.material_override = material

	if letter != null:
		letter.visible = !_uses_model_visual
		letter.text = FALLBACK_LABELS.get(piece_symbol, piece_symbol.to_upper() if !piece_symbol.is_empty() else "?")
		letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED if use_billboard_text else BaseMaterial3D.BILLBOARD_DISABLED
		letter.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

func _clear_visual(visual: Node3D) -> void:
	if visual == null:
		return
	for child in visual.get_children():
		child.free()

func _ensure_move_sfx() -> void:
	if _move_sfx != null:
		return
	var audio_stream_randomizer := AudioStreamRandomizer.new()
	audio_stream_randomizer.random_pitch = 1.3
	audio_stream_randomizer.random_volume_offset_db = 2.0
	audio_stream_randomizer.add_stream(-1, load(MOVE_SFX_PATH))
	_move_sfx = AudioStreamPlayer3D.new()
	_move_sfx.stream = audio_stream_randomizer
	_move_sfx.bus = &"SFX"
	_move_sfx.unit_size = 2.0
	add_child(_move_sfx)

func _play_move_sfx() -> void:
	if _move_sfx == null:
		return
	_move_sfx.play()
