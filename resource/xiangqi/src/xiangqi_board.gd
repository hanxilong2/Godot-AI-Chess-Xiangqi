extends Node3D
class_name XiangqiBoard

signal state_changed(state)
signal square_points_rebuilt()
signal square_clicked(square_index, square_name)
signal selection_changed(square_index, square_name)
signal move_applied(move)
signal move_undone(move)
signal interaction_feedback(message)

const PIECE_SCENE := preload("res://resource/xiangqi/scene/actor/xiangqi_piece_base.tscn")

@export var auto_generate_points: bool = true
@export var spawn_placeholder_pieces: bool = true
@export var interaction_enabled: bool = true
@export var show_debug_points: bool = false
@export var grid_origin: Vector3 = Vector3(-0.33, 0.052, -0.39)
@export var file_spacing: float = 0.0825
@export var rank_spacing: float = 0.086
@export var piece_height_offset: float = 0.012
@export var canvas_surface_lift: float = 0.0095
@export var point_pick_radius: float = 0.045
@export var point_pick_lift: float = 0.034
@export var max_screen_pick_distance: float = 70.0
@export var debug_point_radius: float = 0.004
@export var show_occupied_overlay: bool = false
@export var show_selected_overlay: bool = false
@export var show_last_move_overlay: bool = false
@export var occupied_overlay_color: Color = Color(0.70, 0.18, 0.12, 0.24)
@export var selected_overlay_color: Color = Color(0.176, 0.176, 0.176, 1.0)
@export var legal_overlay_color: Color = Color(0.16, 0.72, 0.30, 1.0)
@export var last_move_overlay_color: Color = Color(0.569, 0.569, 0.569, 1.0)
@export var show_3d_move_hints: bool = false
@export var selected_hint_radius: float = 0.028
@export var legal_hint_radius: float = 0.022
@export var hint_height_offset: float = 0.004

var state: XiangqiState = null
var piece_nodes: Dictionary = {}
var square_nodes: Dictionary = {}
var anchor_nodes: Dictionary = {}
var _debug_point_material: StandardMaterial3D = null
var _selected_square: int = -1
var _selected_moves: Array = []
var _last_move: XiangqiMove = null
var _visual_history: Array = []

@onready var anchors_root: Node3D = $anchors
@onready var points_root: Node3D = $points
@onready var pieces_root: Node3D = $pieces
@onready var canvas: XiangqiCanvas = $canvas
@onready var hints_root: Node3D = get_node_or_null("hints") as Node3D

func _ready() -> void:
	if state == null:
		state = XiangqiFen.create_state()
	_ensure_hints_root()
	refresh_anchor_nodes()
	if auto_generate_points:
		rebuild_square_points()
	refresh_board()

func set_state(new_state: XiangqiState) -> void:
	if new_state == null:
		return
	state = new_state.duplicate()
	_selected_square = -1
	_selected_moves.clear()
	_last_move = null
	_visual_history.clear()
	if is_node_ready():
		refresh_board()
	state_changed.emit(state.duplicate())

func reset_to_start_position() -> void:
	set_state(XiangqiFen.create_state())

func refresh_board() -> void:
	refresh_anchor_nodes()
	if auto_generate_points and square_nodes.is_empty():
		rebuild_square_points()
	refresh_piece_nodes()
	refresh_canvas()
	_align_canvas_to_board()

func rebuild_square_points() -> void:
	if points_root == null:
		return
	for child in points_root.get_children():
		child.queue_free()
	square_nodes.clear()
	for rank: int in XiangqiConstants.BOARD_RANKS:
		for file: int in XiangqiConstants.BOARD_FILES:
			var square_index: int = XiangqiCoord.to_index(file, rank)
			var square_name: String = XiangqiCoord.to_name(file, rank)
			var point := Area3D.new()
			point.name = square_name
			point.position = get_square_position(square_index)
			point.input_ray_pickable = interaction_enabled
			point.set_meta("square_index", square_index)
			var collision_shape := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = point_pick_radius
			collision_shape.position = Vector3(0.0, point_pick_lift, 0.0)
			collision_shape.shape = sphere
			point.add_child(collision_shape)
			if show_debug_points:
				point.add_child(_create_debug_point_mesh())
			point.input_event.connect(_on_square_input_event.bind(square_index))
			points_root.add_child(point)
			square_nodes[square_name] = point
	square_points_rebuilt.emit()

func get_square_position(index: int) -> Vector3:
	var square_name := XiangqiCoord.index_to_name(index)
	var anchor := get_anchor_node(square_name)
	if anchor != null:
		return anchor.position
	var coord: Vector2i = XiangqiCoord.from_index(index)
	return _square_position(coord.x, coord.y)

func get_square_world_position(index: int) -> Vector3:
	return to_global(get_square_position(index) + Vector3(0.0, piece_height_offset, 0.0))

func get_square_node(square_name: String) -> Node3D:
	return square_nodes.get(square_name, null)

func get_anchor_node(square_name: String) -> Marker3D:
	return anchor_nodes.get(square_name, null)

func get_anchor_count() -> int:
	return anchor_nodes.size()

func contains_screen_point(camera: Camera3D, screen_position: Vector2) -> bool:
	return _intersect_board_surface(camera, screen_position) != null

func get_hint_marker_count() -> int:
	return hints_root.get_child_count() if hints_root != null else 0

func get_selected_square() -> int:
	return _selected_square

func get_selected_square_name() -> String:
	return XiangqiCoord.index_to_name(_selected_square) if _selected_square != -1 else ""

func get_legal_target_indices() -> Array:
	var result: Array = []
	for move in _selected_moves:
		result.push_back(move.to_index)
	return result

func can_undo() -> bool:
	return !_visual_history.is_empty()

func click_square_by_name(square_name: String) -> bool:
	return click_square(XiangqiCoord.name_to_index(square_name))

func click_square(square_index: int) -> bool:
	if !interaction_enabled or !XiangqiCoord.is_valid_index(square_index):
		return false

	square_clicked.emit(square_index, XiangqiCoord.index_to_name(square_index))
	if _selected_square != -1:
		if _selected_square == square_index:
			clear_selection()
			return false
		var chosen_move := _find_selected_move(square_index)
		if chosen_move != null:
			return apply_move(chosen_move)

	if _can_select_square(square_index):
		return select_square(square_index)

	interaction_feedback.emit("No legal move for %s." % XiangqiCoord.index_to_name(square_index))
	return false

func select_square(square_index: int) -> bool:
	if !XiangqiCoord.is_valid_index(square_index):
		clear_selection()
		return false
	if !_can_select_square(square_index):
		clear_selection()
		return false

	if _selected_square != square_index:
		_idle_selected_piece()
	_selected_square = square_index
	_selected_moves = XiangqiRules.generate_legal_moves(state, state.side_to_move, square_index)
	_ready_selected_piece()
	selection_changed.emit(square_index, XiangqiCoord.index_to_name(square_index))
	refresh_canvas()
	return true

func clear_selection() -> void:
	if _selected_square == -1 and _selected_moves.is_empty():
		return
	_idle_selected_piece()
	_selected_square = -1
	_selected_moves.clear()
	selection_changed.emit(-1, "")
	refresh_canvas()

func apply_move(move: XiangqiMove, animate: bool = true) -> bool:
	if move == null:
		return false

	var legal_move: XiangqiMove = _resolve_legal_move(move)
	if legal_move == null:
		interaction_feedback.emit("Illegal move: %s" % move.to_coordinate_string())
		return false

	var moving_piece: XiangqiPiece = piece_nodes.get(legal_move.from_index, null)
	if moving_piece == null:
		refresh_piece_nodes()
		moving_piece = piece_nodes.get(legal_move.from_index, null)
	if moving_piece == null:
		return false

	moving_piece.idle()
	var captured_piece: XiangqiPiece = piece_nodes.get(legal_move.to_index, null)
	var history_entry := {
		"move": legal_move.duplicate(),
		"captured_piece": captured_piece,
		"previous_last_move": _last_move.duplicate() if _last_move != null else null,
	}

	piece_nodes.erase(legal_move.from_index)
	if captured_piece != null:
		piece_nodes.erase(legal_move.to_index)
	piece_nodes[legal_move.to_index] = moving_piece

	state.apply_move(legal_move)
	_last_move = legal_move.duplicate()
	_visual_history.push_back(history_entry)

	if animate:
		_play_move_animation(moving_piece, captured_piece, legal_move)
	else:
		moving_piece.global_position = get_square_world_position(legal_move.to_index)
		if captured_piece != null:
			captured_piece.visible = false

	_selected_square = -1
	_selected_moves.clear()
	refresh_canvas()
	state_changed.emit(state.duplicate())
	move_applied.emit(legal_move.duplicate())
	return true

func undo_last_move(animate: bool = true) -> bool:
	if _visual_history.is_empty():
		return false

	var history_entry: Dictionary = _visual_history.pop_back()
	var move: XiangqiMove = history_entry["move"]
	var moving_piece: XiangqiPiece = piece_nodes.get(move.to_index, null)
	if moving_piece == null:
		return false
	moving_piece.idle()

	piece_nodes.erase(move.to_index)
	piece_nodes[move.from_index] = moving_piece

	var captured_piece: XiangqiPiece = history_entry["captured_piece"]
	if captured_piece != null:
		piece_nodes[move.to_index] = captured_piece

	state.undo_move()
	_last_move = history_entry["previous_last_move"]

	if animate:
		moving_piece.move(get_square_world_position(move.from_index))
		if captured_piece != null:
			captured_piece.introduce(get_square_world_position(move.to_index))
	else:
		moving_piece.global_position = get_square_world_position(move.from_index)
		if captured_piece != null:
			captured_piece.visible = true
			captured_piece.global_position = get_square_world_position(move.to_index)

	_selected_square = -1
	_selected_moves.clear()
	refresh_canvas()
	state_changed.emit(state.duplicate())
	move_undone.emit(move.duplicate())
	return true

func refresh_piece_nodes() -> void:
	if pieces_root == null:
		return
	for child in pieces_root.get_children():
		child.queue_free()
	piece_nodes.clear()
	if !spawn_placeholder_pieces or state == null:
		return
	for index: int in XiangqiConstants.BOARD_SIZE:
		var symbol: String = state.get_piece_at(index)
		if symbol.is_empty():
			continue
		var piece_instance: XiangqiPiece = PIECE_SCENE.instantiate()
		piece_instance.name = "piece_%s" % XiangqiCoord.index_to_name(index)
		piece_instance.setup(symbol)
		pieces_root.add_child(piece_instance)
		piece_instance.global_position = get_square_world_position(index)
		piece_nodes[index] = piece_instance

func refresh_anchor_nodes() -> void:
	anchor_nodes.clear()
	if anchors_root == null:
		return
	for child in anchors_root.get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		anchor_nodes[String(marker.name)] = marker

func refresh_canvas() -> void:
	if canvas == null or state == null:
		return

	if show_occupied_overlay:
		var occupied_squares: Array = []
		for index: int in XiangqiConstants.BOARD_SIZE:
			if state.has_piece_at(index):
				occupied_squares.push_back(XiangqiCoord.index_to_name(index))
		canvas.draw_points("occupied", occupied_squares, occupied_overlay_color)
	else:
		canvas.clear_layer("occupied")

	if show_last_move_overlay and _last_move != null:
		canvas.draw_points(
			"last_move",
			[
				XiangqiCoord.index_to_name(_last_move.from_index),
				XiangqiCoord.index_to_name(_last_move.to_index),
			],
			last_move_overlay_color
		)
	else:
		canvas.clear_layer("last_move")

	if _selected_square != -1:
		if show_selected_overlay:
			canvas.draw_points("selected", [XiangqiCoord.index_to_name(_selected_square)], selected_overlay_color)
		else:
			canvas.clear_layer("selected")
		var legal_squares: Array = []
		for move in _selected_moves:
			legal_squares.push_back(XiangqiCoord.index_to_name(move.to_index))
		canvas.draw_points("legal", legal_squares, legal_overlay_color)
	else:
		canvas.clear_layer("selected")
		canvas.clear_layer("legal")
	refresh_3d_hints()

func refresh_3d_hints() -> void:
	_ensure_hints_root()
	if hints_root == null:
		return
	for child in hints_root.get_children():
		child.free()
	if !show_3d_move_hints or _selected_square == -1:
		return

	_add_hint_marker(
		"selected_%s" % XiangqiCoord.index_to_name(_selected_square),
		_selected_square,
		selected_hint_radius,
		selected_overlay_color
	)
	for move in _selected_moves:
		_add_hint_marker(
			"legal_%s" % XiangqiCoord.index_to_name(move.to_index),
			move.to_index,
			legal_hint_radius,
			legal_overlay_color
		)

func _on_square_input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int, square_index: int) -> void:
	if !interaction_enabled:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or !mouse_event.pressed:
		return
	get_viewport().set_input_as_handled()
	var picked_square := _pick_square_from_screen(mouse_event.position)
	click_square(picked_square if picked_square != -1 else square_index)

func _unhandled_input(event: InputEvent) -> void:
	if !interaction_enabled:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or !mouse_event.pressed:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var square_index := _pick_square_from_screen(mouse_event.position)
	if square_index == -1:
		return
	get_viewport().set_input_as_handled()
	click_square(square_index)

func _pick_square_from_screen(screen_position: Vector2) -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return -1

	var best_index := -1
	var best_distance := INF
	for index: int in XiangqiConstants.BOARD_SIZE:
		var world_position := get_square_world_position(index)
		if camera.is_position_behind(world_position):
			continue
		var projected_position := camera.unproject_position(world_position)
		var distance := projected_position.distance_to(screen_position)
		if distance < best_distance:
			best_distance = distance
			best_index = index

	return best_index if best_distance <= max_screen_pick_distance else -1

func _intersect_board_surface(camera: Camera3D, screen_position: Vector2) -> Variant:
	if camera == null:
		return null
	if anchor_nodes.is_empty():
		refresh_anchor_nodes()
	if anchor_nodes.is_empty():
		return null

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var average_y := 0.0
	var count := 0
	for marker_variant in anchor_nodes.values():
		var marker := marker_variant as Marker3D
		if marker == null:
			continue
		min_x = minf(min_x, marker.position.x)
		max_x = maxf(max_x, marker.position.x)
		min_z = minf(min_z, marker.position.z)
		max_z = maxf(max_z, marker.position.z)
		average_y += marker.position.y
		count += 1
	if count == 0:
		return null
	average_y /= float(count)

	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position).normalized()
	var surface_normal := global_transform.basis.y.normalized()
	var denominator := surface_normal.dot(ray_direction)
	if absf(denominator) <= 0.00001:
		return null

	var surface_point := to_global(Vector3(0.0, average_y, 0.0))
	var distance := surface_normal.dot(surface_point - ray_origin) / denominator
	if distance < 0.0:
		return null

	var hit_point := ray_origin + ray_direction * distance
	var local_hit := to_local(hit_point)
	var file_margin := ((max_x - min_x) / float(maxi(1, XiangqiConstants.BOARD_FILES - 1))) * 0.5
	var rank_margin := ((max_z - min_z) / float(maxi(1, XiangqiConstants.BOARD_RANKS - 1))) * 0.5
	if local_hit.x < min_x - file_margin or local_hit.x > max_x + file_margin:
		return null
	if local_hit.z < min_z - rank_margin or local_hit.z > max_z + rank_margin:
		return null
	return hit_point

func _can_select_square(square_index: int) -> bool:
	if state == null or !state.has_piece_at(square_index):
		return false
	return state.get_piece_side(square_index) == state.side_to_move and XiangqiRules.has_any_legal_move(state, state.side_to_move, square_index)

func _resolve_legal_move(move: XiangqiMove) -> XiangqiMove:
	for legal_move in XiangqiRules.generate_legal_moves(state, state.side_to_move, move.from_index):
		if legal_move.from_index == move.from_index and legal_move.to_index == move.to_index:
			return legal_move
	return null

func _find_selected_move(target_square: int) -> XiangqiMove:
	for move in _selected_moves:
		if move.to_index == target_square:
			return move
	return null

func _ready_selected_piece() -> void:
	if _selected_square == -1:
		return
	var piece := piece_nodes.get(_selected_square, null) as XiangqiPiece
	if piece != null:
		piece.ready_to_move()

func _idle_selected_piece() -> void:
	if _selected_square == -1:
		return
	var piece := piece_nodes.get(_selected_square, null) as XiangqiPiece
	if piece != null:
		piece.idle()

func _play_move_animation(moving_piece: XiangqiPiece, captured_piece: XiangqiPiece, move: XiangqiMove) -> void:
	var target_position: Vector3 = get_square_world_position(move.to_index)
	if captured_piece != null:
		moving_piece.capturing(target_position, captured_piece)
	else:
		moving_piece.move(target_position)

func _ensure_hints_root() -> void:
	if hints_root != null:
		return
	hints_root = get_node_or_null("hints") as Node3D
	if hints_root != null:
		return
	hints_root = Node3D.new()
	hints_root.name = "hints"
	add_child(hints_root)

func _add_hint_marker(marker_name: String, square_index: int, radius: float, color: Color) -> void:
	if hints_root == null:
		return
	var marker := MeshInstance3D.new()
	marker.name = marker_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.003
	cylinder.radial_segments = 40
	marker.mesh = cylinder
	marker.material_override = _create_hint_material(color)
	hints_root.add_child(marker)
	marker.global_position = get_square_world_position(square_index) + Vector3(0.0, hint_height_offset, 0.0)

func _create_hint_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, minf(color.a, 0.78))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material

func _align_canvas_to_board() -> void:
	if canvas == null or anchor_nodes.is_empty():
		return

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var average_y := 0.0
	var count := 0

	for marker_variant in anchor_nodes.values():
		var marker := marker_variant as Marker3D
		if marker == null:
			continue
		var marker_position := marker.position
		min_x = minf(min_x, marker_position.x)
		max_x = maxf(max_x, marker_position.x)
		min_z = minf(min_z, marker_position.z)
		max_z = maxf(max_z, marker_position.z)
		average_y += marker_position.y
		count += 1

	if count == 0:
		return

	canvas.position = Vector3(
		(min_x + max_x) * 0.5,
		average_y / float(count) + canvas_surface_lift,
		(min_z + max_z) * 0.5
	)

	var mesh_instance := canvas.get_node_or_null("mesh_instance") as MeshInstance3D
	if mesh_instance == null:
		return
	var plane := mesh_instance.mesh as PlaneMesh
	if plane == null:
		return
	var aligned_plane := plane.duplicate() as PlaneMesh
	var board_width := max_x - min_x
	var board_height := absf(max_z - min_z)
	aligned_plane.size = Vector2(
		board_width * float(XiangqiConstants.BOARD_FILES) / float(XiangqiConstants.BOARD_FILES - 1),
		board_height * float(XiangqiConstants.BOARD_RANKS) / float(XiangqiConstants.BOARD_RANKS - 1)
	)
	mesh_instance.mesh = aligned_plane

func _square_position(file: int, rank: int) -> Vector3:
	return grid_origin + Vector3(file * file_spacing, 0.0, rank * rank_spacing)

func _create_debug_point_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = debug_point_radius
	sphere.height = debug_point_radius * 2.0
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _get_debug_point_material()
	return mesh_instance

func _get_debug_point_material() -> StandardMaterial3D:
	if _debug_point_material == null:
		_debug_point_material = StandardMaterial3D.new()
		_debug_point_material.albedo_color = Color(0.79, 0.17, 0.14, 0.70)
		_debug_point_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_debug_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _debug_point_material
