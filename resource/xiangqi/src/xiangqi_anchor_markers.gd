@tool
extends Node3D
class_name XiangqiAnchorMarkers

const FILE_ORIGIN_X := -0.1924955
const FILE_STEP_X := 0.048718375
const RANK_ORIGIN_Z := -0.13088831305504
const RANK_STEP_Z := -0.04819755698424

@export var anchor_y: float = 0.0508
@export var marker_gizmo_size: float = 0.01
@export var lock_to_calibrated_layout: bool = true

func _ready() -> void:
	if lock_to_calibrated_layout and !_markers_match_layout():
		_rebuild_markers()

func _rebuild_markers() -> void:
	for child in get_children():
		child.free()

	for rank: int in XiangqiConstants.BOARD_RANKS:
		for file: int in XiangqiConstants.BOARD_FILES:
			var marker := Marker3D.new()
			marker.name = XiangqiCoord.to_name(file, rank)
			marker.position = _marker_position(file, rank)
			marker.gizmo_extents = marker_gizmo_size
			add_child(marker)
			if Engine.is_editor_hint():
				marker.owner = get_tree().edited_scene_root

func _markers_match_layout() -> bool:
	if get_child_count() != XiangqiConstants.BOARD_SIZE:
		return false
	for rank: int in XiangqiConstants.BOARD_RANKS:
		for file: int in XiangqiConstants.BOARD_FILES:
			var square_name := XiangqiCoord.to_name(file, rank)
			var marker := get_node_or_null(square_name) as Marker3D
			if marker == null:
				return false
			if !marker.position.is_equal_approx(_marker_position(file, rank)):
				return false
	return true

func _marker_position(file: int, rank: int) -> Vector3:
	return Vector3(
		FILE_ORIGIN_X + FILE_STEP_X * file,
		anchor_y,
		RANK_ORIGIN_Z + RANK_STEP_Z * rank
	)
