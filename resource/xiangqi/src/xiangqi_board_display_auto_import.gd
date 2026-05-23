@tool
extends Node3D

const DISPLAY_SCALE := 0.11
const DISPLAY_OFFSET := Vector3(0.0, 0.024, -0.347)
const BOARD_MESH_NAME := "W001"

@onready var xiangqi_model: Node3D = $xiangqi_model

func _ready() -> void:
	_apply_display_setup()

func _apply_display_setup() -> void:
	if xiangqi_model == null:
		return

	xiangqi_model.scale = Vector3.ONE * DISPLAY_SCALE
	xiangqi_model.position = DISPLAY_OFFSET

	_set_descendants_visible(xiangqi_model, false)
	xiangqi_model.visible = true

	var board_mesh := xiangqi_model.find_child(BOARD_MESH_NAME, true, false) as Node3D
	if board_mesh == null:
		return
	_set_branch_visible(board_mesh)

func _set_descendants_visible(node: Node, should_show: bool) -> void:
	for child: Node in node.get_children():
		if child is Node3D:
			(child as Node3D).visible = should_show
		_set_descendants_visible(child, should_show)

func _set_branch_visible(node: Node3D) -> void:
	var current: Node = node
	while current != null:
		if current is Node3D:
			(current as Node3D).visible = true
		if current == xiangqi_model:
			return
		current = current.get_parent()
