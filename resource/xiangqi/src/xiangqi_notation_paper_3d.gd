extends Node3D
class_name XiangqiNotationPaper3D

const FALLBACK_MAX_INFO_LINES := 10
@export var sheet_surface_size := Vector2(0.232, 0.324)
@export var stack_fill_ratio := Vector2(0.94, 0.94)
@export var sheet_surface_lift := 0.0012
@export_range(0.0, 0.45, 0.01) var page_turn_dead_zone_ratio := 0.08

var _pending_entries: Array = []

@onready var paper_stack: Node3D = $paper_stack
@onready var sheet_surface: MeshInstance3D = $paper_stack/sheet_surface
@onready var sub_viewport: SubViewport = $sub_viewport
@onready var move_sheet: XiangqiMoveSheet = $sub_viewport/xiangqi_move_sheet

func _ready() -> void:
	_apply_viewport_texture()
	_refresh_sheet_surface()
	_align_sheet_surface()
	if _pending_entries.is_empty():
		move_sheet.clear_entries()
	else:
		move_sheet.set_entries(_pending_entries)
	_request_viewport_update()

func set_entries(entries: Array) -> void:
	_pending_entries = entries.duplicate(true)
	if is_node_ready():
		move_sheet.set_entries(_pending_entries)
		_request_viewport_update()

func clear_entries() -> void:
	set_entries([])

func get_entry_count() -> int:
	if is_node_ready():
		return move_sheet.get_entry_count()
	return _pending_entries.size()

func get_page_count() -> int:
	if is_node_ready():
		return move_sheet.get_page_count()
	return maxi(1, int(ceil(float(_count_pending_info_lines()) / float(FALLBACK_MAX_INFO_LINES))))

func get_current_page() -> int:
	if is_node_ready():
		return move_sheet.get_current_page()
	return max(0, get_page_count() - 1)

func can_turn_page(delta: int) -> bool:
	if is_node_ready():
		return move_sheet.can_turn_page(delta)
	var target_page := get_current_page() + delta
	return target_page >= 0 and target_page < get_page_count()

func turn_page(delta: int) -> bool:
	if is_node_ready():
		var turned := bool(move_sheet.turn_page(delta))
		if turned:
			_request_viewport_update()
		return turned
	return false

func contains_screen_point(camera: Camera3D, screen_position: Vector2) -> bool:
	return _intersect_sheet_surface(camera, screen_position) != null

func handle_click(camera: Camera3D, screen_position: Vector2) -> bool:
	var page_delta := get_click_page_delta(camera, screen_position)
	if page_delta == 0:
		return false
	if !can_turn_page(page_delta):
		return true
	return turn_page(page_delta)

func get_surface_focus_point() -> Vector3:
	if sheet_surface == null:
		return global_position
	return sheet_surface.global_position

func get_surface_normal() -> Vector3:
	if sheet_surface == null:
		return global_transform.basis.y.normalized()
	var normal := sheet_surface.global_transform.basis.y
	if normal.length_squared() <= 0.000001:
		return Vector3.UP
	return normal.normalized()

func get_surface_page_up(reference_camera: Camera3D = null) -> Vector3:
	if sheet_surface == null:
		return Vector3.BACK

	var page_up := sheet_surface.global_transform.basis.z
	if page_up.length_squared() <= 0.000001:
		return Vector3.BACK
	page_up = page_up.normalized()

	if reference_camera == null:
		return -page_up

	var plane: PlaneMesh = sheet_surface.mesh as PlaneMesh
	var sample_distance := 0.04
	if plane != null:
		sample_distance = maxf(sample_distance, plane.size.y * 0.2)

	var focus := get_surface_focus_point()
	var positive_screen := reference_camera.unproject_position(focus + page_up * sample_distance)
	var negative_screen := reference_camera.unproject_position(focus - page_up * sample_distance)
	return page_up if positive_screen.y < negative_screen.y else -page_up

func get_click_page_delta(camera: Camera3D, screen_position: Vector2) -> int:
	if camera == null or sheet_surface == null:
		return 0

	var hit_point: Variant = _intersect_sheet_surface(camera, screen_position)
	if hit_point == null:
		return 0

	var local_hit: Vector3 = sheet_surface.to_local(hit_point)
	var plane: PlaneMesh = sheet_surface.mesh as PlaneMesh
	if plane == null:
		return 0
	var half_width := plane.size.x * 0.5
	if half_width <= 0.0001:
		return 0
	var dead_zone := half_width * page_turn_dead_zone_ratio
	if local_hit.x < -dead_zone:
		return -1
	if local_hit.x > dead_zone:
		return 1
	return 0

func show_latest_page() -> void:
	if is_node_ready():
		move_sheet.show_latest_page()
		_request_viewport_update()

func set_title_text(value: String) -> void:
	if is_node_ready():
		move_sheet.set_title_text(value)
		_request_viewport_update()

func _request_viewport_update() -> void:
	if sub_viewport != null:
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _apply_viewport_texture() -> void:
	var base_material: StandardMaterial3D = sheet_surface.get_surface_override_material(0) as StandardMaterial3D
	if base_material == null:
		base_material = StandardMaterial3D.new()
	var configured_material: StandardMaterial3D = base_material.duplicate() as StandardMaterial3D
	configured_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	configured_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	configured_material.albedo_texture = sub_viewport.get_texture()
	sheet_surface.set_surface_override_material(0, configured_material)

func _refresh_sheet_surface() -> void:
	var stack_aabb: AABB = _get_combined_mesh_aabb(paper_stack)
	var plane: PlaneMesh = sheet_surface.mesh as PlaneMesh
	if plane == null:
		return
	var configured_plane: PlaneMesh = plane.duplicate() as PlaneMesh
	if stack_aabb.size.x > 0.0001 and stack_aabb.size.z > 0.0001:
		configured_plane.size = Vector2(
			stack_aabb.size.x * stack_fill_ratio.x,
			stack_aabb.size.z * stack_fill_ratio.y
		)
	else:
		configured_plane.size = sheet_surface_size
	sheet_surface.mesh = configured_plane

func _align_sheet_surface() -> void:
	if sheet_surface == null:
		return
	var stack_aabb: AABB = _get_combined_mesh_aabb(paper_stack)
	if stack_aabb.size == Vector3.ZERO:
		sheet_surface.position = Vector3(0.0, sheet_surface_lift, 0.0)
		return

	var center: Vector3 = stack_aabb.position + stack_aabb.size * 0.5
	sheet_surface.position = Vector3(
		center.x,
		stack_aabb.position.y + stack_aabb.size.y + sheet_surface_lift,
		center.z
	)

func _get_combined_mesh_aabb(root: Node3D) -> AABB:
	if root == null:
		return AABB()

	var has_point := false
	var min_point := Vector3.ZERO
	var max_point := Vector3.ZERO
	for mesh_instance_variant in _collect_mesh_instances(root):
		var mesh_instance: MeshInstance3D = mesh_instance_variant as MeshInstance3D
		if mesh_instance == null or mesh_instance == sheet_surface or mesh_instance.mesh == null:
			continue
		for corner_variant in _get_aabb_corners(mesh_instance.mesh.get_aabb()):
			var corner: Vector3 = corner_variant
			var point: Vector3 = root.to_local(mesh_instance.to_global(corner))
			if !has_point:
				min_point = point
				max_point = point
				has_point = true
				continue
			min_point = Vector3(
				minf(min_point.x, point.x),
				minf(min_point.y, point.y),
				minf(min_point.z, point.z)
			)
			max_point = Vector3(
				maxf(max_point.x, point.x),
				maxf(max_point.y, point.y),
				maxf(max_point.z, point.z)
			)

	if !has_point:
		return AABB()
	return AABB(min_point, max_point - min_point)

func _collect_mesh_instances(root: Node) -> Array:
	var result: Array = []
	for child in root.get_children():
		if child is MeshInstance3D:
			result.push_back(child)
		if child is Node:
			result.append_array(_collect_mesh_instances(child))
	return result

func _get_aabb_corners(box: AABB) -> Array:
	var start: Vector3 = box.position
	var end: Vector3 = box.position + box.size
	return [
		Vector3(start.x, start.y, start.z),
		Vector3(end.x, start.y, start.z),
		Vector3(start.x, end.y, start.z),
		Vector3(start.x, start.y, end.z),
		Vector3(end.x, end.y, start.z),
		Vector3(end.x, start.y, end.z),
		Vector3(start.x, end.y, end.z),
		Vector3(end.x, end.y, end.z),
	]

func _count_pending_info_lines() -> int:
	var count := 0
	for row_variant in _pending_entries:
		var row := row_variant as Dictionary
		if row == null:
			continue
		if !String(row.get("red", "")).strip_edges().is_empty():
			count += 1
		if !String(row.get("black", "")).strip_edges().is_empty():
			count += 1
	return count

func _intersect_sheet_surface(camera: Camera3D, screen_position: Vector2) -> Variant:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position).normalized()
	var surface_normal: Vector3 = sheet_surface.global_transform.basis.y.normalized()
	var denominator := surface_normal.dot(ray_direction)
	if absf(denominator) <= 0.00001:
		return null

	var distance := surface_normal.dot(sheet_surface.global_position - ray_origin) / denominator
	if distance < 0.0:
		return null

	var hit_point := ray_origin + ray_direction * distance
	var local_hit: Vector3 = sheet_surface.to_local(hit_point)
	var plane: PlaneMesh = sheet_surface.mesh as PlaneMesh
	if plane == null:
		return null
	if absf(local_hit.x) > plane.size.x * 0.5 or absf(local_hit.z) > plane.size.y * 0.5:
		return null
	return hit_point
