extends RefCounted
class_name XiangqiPieceLibrary

const MODEL_SCENE := preload("res://assets/model/xiangqi/piece_set/象棋.fbx")
const MODEL_VISUAL_SCALE := 0.105
const MERGED_BLACK_PAWN_CLUSTER_INDEX := 2
const MERGED_BLACK_PAWN_CLUSTER_COUNT := 5

const TEMPLATE_NODE_NAMES := {
	"R": "車_1",
	"H": "马",
	"E": "相",
	"A": "仕",
	"K": "仕_2",
	"C": "仕_3",
	"P": "兵",
	"r": "車_2",
	"h": "ma",
	"e": "向",
	"a": "士",
	"k": "将",
	"c": "炮",
	"p": "卒",
}

static var _template_cache: Dictionary = {}

static func instantiate_visual(piece_symbol: String) -> Node3D:
	var normalized := XiangqiConstants.normalize_piece(piece_symbol)
	if normalized.is_empty():
		return null

	var template_scene := _get_template_scene(normalized)
	if template_scene == null:
		return null

	var visual_root := Node3D.new()
	visual_root.name = "model"
	visual_root.scale = Vector3.ONE * MODEL_VISUAL_SCALE

	var piece_node := template_scene.instantiate() as Node3D
	if piece_node == null:
		return null
	piece_node.name = "mesh"
	piece_node.position = Vector3.ZERO
	piece_node.rotation = Vector3.ZERO
	piece_node.scale = Vector3.ONE
	visual_root.add_child(piece_node)
	_center_visual_on_origin(piece_node)
	return visual_root

static func _get_template_scene(piece_symbol: String) -> PackedScene:
	if _template_cache.has(piece_symbol):
		return _template_cache[piece_symbol] as PackedScene

	var scene_root := MODEL_SCENE.instantiate()
	var node_name := TEMPLATE_NODE_NAMES.get(piece_symbol, "") as String
	if node_name.is_empty():
		scene_root.free()
		return null

	var source_node := scene_root.find_child(node_name, true, false) as Node3D
	if source_node == null:
		scene_root.free()
		return null

	var template: Node3D
	if piece_symbol == "p":
		template = _create_single_black_pawn_template(source_node)
	else:
		template = source_node.duplicate() as Node3D
	scene_root.free()
	if template == null:
		return null

	template.name = node_name
	template.position = Vector3.ZERO
	template.rotation = Vector3.ZERO
	template.scale = Vector3.ONE
	_assign_owner(template, template)

	var packed_scene := PackedScene.new()
	if packed_scene.pack(template) != OK:
		template.free()
		return null
	template.free()

	_template_cache[piece_symbol] = packed_scene
	return packed_scene

static func _assign_owner(node: Node, owner: Node) -> void:
	if node != owner:
		node.owner = owner
	for child in node.get_children():
		_assign_owner(child, owner)

static func _create_single_black_pawn_template(source_node: Node3D) -> Node3D:
	var source_mesh := source_node as MeshInstance3D
	if source_mesh == null or source_mesh.mesh == null:
		return source_node.duplicate() as Node3D

	var body_extract := _extract_mesh_x_cluster(
		source_mesh.mesh,
		MERGED_BLACK_PAWN_CLUSTER_INDEX,
		MERGED_BLACK_PAWN_CLUSTER_COUNT
	)
	if body_extract.is_empty():
		return source_node.duplicate() as Node3D

	var pawn := MeshInstance3D.new()
	pawn.name = source_node.name
	pawn.mesh = body_extract["mesh"] as ArrayMesh
	_copy_mesh_instance_settings(source_mesh, pawn)

	var offset := body_extract["offset"] as Vector3
	for child in source_node.get_children():
		var child_mesh := child as MeshInstance3D
		if child_mesh == null or child_mesh.mesh == null:
			continue
		var child_extract := _extract_mesh_x_cluster(
			child_mesh.mesh,
			MERGED_BLACK_PAWN_CLUSTER_INDEX,
			MERGED_BLACK_PAWN_CLUSTER_COUNT,
			offset
		)
		if child_extract.is_empty():
			continue
		var child_copy := MeshInstance3D.new()
		child_copy.name = child.name
		child_copy.mesh = child_extract["mesh"] as ArrayMesh
		_copy_mesh_instance_settings(child_mesh, child_copy)
		pawn.add_child(child_copy)

	return pawn

static func _copy_mesh_instance_settings(source: MeshInstance3D, target: MeshInstance3D) -> void:
	target.material_override = source.material_override
	target.cast_shadow = source.cast_shadow
	target.transparency = source.transparency
	for surface_index: int in source.mesh.get_surface_count():
		var material := source.get_surface_override_material(surface_index)
		if material != null and surface_index < target.mesh.get_surface_count():
			target.set_surface_override_material(surface_index, material)

static func _center_visual_on_origin(root: Node3D) -> void:
	var aabb_result: Dictionary = _combined_mesh_aabb(root)
	if !bool(aabb_result["has_aabb"]):
		return
	var visual_aabb: AABB = aabb_result["aabb"]
	var center: Vector3 = visual_aabb.get_center()
	root.position -= Vector3(center.x, 0.0, center.z)

static func _combined_mesh_aabb(root: Node3D) -> Dictionary:
	var combined := AABB()
	var has_aabb := false
	var mesh_nodes: Array = []
	if root is MeshInstance3D:
		mesh_nodes.push_back(root)
	mesh_nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))

	for node in mesh_nodes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_aabb := _transform_aabb(
			mesh_instance.mesh.get_aabb(),
			_transform_to_root(mesh_instance, root)
		)
		combined = local_aabb if !has_aabb else combined.merge(local_aabb)
		has_aabb = true

	return {
		"has_aabb": has_aabb,
		"aabb": combined,
	}

static func _transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var current_node := current as Node3D
		if current_node == null:
			break
		result = current_node.transform * result
		current = current.get_parent()
	return result

static func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var corners := [
		aabb.position,
		Vector3(aabb.end.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.end.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.end.z),
		aabb.end,
	]
	var transformed := AABB(transform * corners[0], Vector3.ZERO)
	for index: int in range(1, corners.size()):
		transformed = transformed.expand(transform * corners[index])
	return transformed

static func _extract_mesh_x_cluster(
	mesh: Mesh,
	cluster_index: int,
	cluster_count: int,
	offset_override: Variant = null
) -> Dictionary:
	var triangle_centers := _collect_triangle_centers(mesh)
	if triangle_centers.is_empty():
		return {}

	var ranges := _cluster_ranges_from_values(triangle_centers, cluster_count)
	if ranges.is_empty():
		return {}

	var range_index: int = clampi(cluster_index, 0, ranges.size() - 1)
	var target_range := ranges[range_index] as Vector2
	var selected_aabb := AABB()
	var has_aabb := false
	var extracted_surfaces: Array = []

	for surface_index: int in mesh.get_surface_count():
		var surface_result := _extract_surface_x_range(
			mesh,
			surface_index,
			target_range,
			Vector3.ZERO,
			true
		)
		if surface_result.is_empty():
			continue
		var surface_aabb := surface_result["aabb"] as AABB
		selected_aabb = surface_aabb if !has_aabb else selected_aabb.merge(surface_aabb)
		has_aabb = true
		extracted_surfaces.push_back(surface_index)

	if !has_aabb:
		return {}

	var offset: Vector3
	if offset_override is Vector3:
		offset = offset_override as Vector3
	else:
		offset = Vector3(
			(selected_aabb.position.x + selected_aabb.end.x) * 0.5,
			0.0,
			(selected_aabb.position.z + selected_aabb.end.z) * 0.5
		)

	var extracted_mesh := ArrayMesh.new()
	extracted_mesh.resource_local_to_scene = true
	for surface_index_variant in extracted_surfaces:
		var surface_index := int(surface_index_variant)
		var surface_result := _extract_surface_x_range(mesh, surface_index, target_range, offset, false)
		if surface_result.is_empty():
			continue
		var arrays := surface_result["arrays"] as Array
		extracted_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := mesh.surface_get_material(surface_index)
		if material != null:
			extracted_mesh.surface_set_material(extracted_mesh.get_surface_count() - 1, material)

	if extracted_mesh.get_surface_count() == 0:
		return {}
	return {
		"mesh": extracted_mesh,
		"offset": offset,
	}

static func _collect_triangle_centers(mesh: Mesh) -> Array:
	var centers: Array = []
	for surface_index: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices := _as_vector3_array(arrays[Mesh.ARRAY_VERTEX])
		var indices := _as_int32_array(arrays[Mesh.ARRAY_INDEX])
		for triangle in _surface_index_triangles(vertices, indices):
			var tri := triangle as PackedInt32Array
			var center_x := (vertices[tri[0]].x + vertices[tri[1]].x + vertices[tri[2]].x) / 3.0
			centers.push_back(center_x)
	return centers

static func _cluster_ranges_from_values(values: Array, cluster_count: int) -> Array:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	if sorted_values.is_empty():
		return []
	if cluster_count <= 1 or sorted_values.size() <= cluster_count:
		return [Vector2(float(sorted_values.front()), float(sorted_values.back()))]

	var gaps: Array = []
	for index: int in range(sorted_values.size() - 1):
		gaps.push_back({
			"index": index,
			"gap": float(sorted_values[index + 1]) - float(sorted_values[index]),
		})
	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["gap"]) > float(b["gap"])
	)

	var separators: Array = []
	for gap_index: int in range(mini(cluster_count - 1, gaps.size())):
		separators.push_back(int((gaps[gap_index] as Dictionary)["index"]))
	separators.sort()

	var ranges: Array = []
	var start_index := 0
	for separator_variant in separators:
		var separator := int(separator_variant)
		ranges.push_back(_range_for_sorted_values(sorted_values, start_index, separator))
		start_index = separator + 1
	ranges.push_back(_range_for_sorted_values(sorted_values, start_index, sorted_values.size() - 1))
	return ranges

static func _range_for_sorted_values(sorted_values: Array, start_index: int, end_index: int) -> Vector2:
	var padding := 0.001
	return Vector2(
		float(sorted_values[start_index]) - padding,
		float(sorted_values[end_index]) + padding
	)

static func _extract_surface_x_range(
	mesh: Mesh,
	surface_index: int,
	x_range: Vector2,
	offset: Vector3,
	aabb_only: bool
) -> Dictionary:
	var source_arrays := mesh.surface_get_arrays(surface_index)
	var source_vertices := _as_vector3_array(source_arrays[Mesh.ARRAY_VERTEX])
	var source_normals := _as_vector3_array(source_arrays[Mesh.ARRAY_NORMAL])
	var source_uvs := _as_vector2_array(source_arrays[Mesh.ARRAY_TEX_UV])
	var source_indices := _as_int32_array(source_arrays[Mesh.ARRAY_INDEX])

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var selected_aabb := AABB()
	var has_aabb := false

	for triangle in _surface_index_triangles(source_vertices, source_indices):
		var tri := triangle as PackedInt32Array
		var v0 := source_vertices[tri[0]]
		var v1 := source_vertices[tri[1]]
		var v2 := source_vertices[tri[2]]
		var center_x := (v0.x + v1.x + v2.x) / 3.0
		if center_x < x_range.x or center_x > x_range.y:
			continue

		for vertex_index in tri:
			var source_vertex := source_vertices[vertex_index]
			selected_aabb = AABB(source_vertex, Vector3.ZERO) if !has_aabb else selected_aabb.expand(source_vertex)
			has_aabb = true
			if aabb_only:
				continue

			vertices.push_back(source_vertex - offset)
			if source_normals.size() == source_vertices.size():
				normals.push_back(source_normals[vertex_index])
			if source_uvs.size() == source_vertices.size():
				uvs.push_back(source_uvs[vertex_index])

	if !has_aabb:
		return {}
	if aabb_only:
		return {"aabb": selected_aabb}

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if normals.size() == vertices.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if uvs.size() == vertices.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	return {
		"arrays": arrays,
		"aabb": selected_aabb,
	}

static func _surface_index_triangles(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var result: Array = []
	if indices.is_empty():
		for index: int in range(0, vertices.size() - 2, 3):
			var triangle := PackedInt32Array()
			triangle.push_back(index)
			triangle.push_back(index + 1)
			triangle.push_back(index + 2)
			result.push_back(triangle)
	else:
		for index: int in range(0, indices.size() - 2, 3):
			var triangle := PackedInt32Array()
			triangle.push_back(indices[index])
			triangle.push_back(indices[index + 1])
			triangle.push_back(indices[index + 2])
			result.push_back(triangle)
	return result

static func _as_vector3_array(value: Variant) -> PackedVector3Array:
	if value is PackedVector3Array:
		return value as PackedVector3Array
	return PackedVector3Array()

static func _as_vector2_array(value: Variant) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value as PackedVector2Array
	return PackedVector2Array()

static func _as_int32_array(value: Variant) -> PackedInt32Array:
	if value is PackedInt32Array:
		return value as PackedInt32Array
	return PackedInt32Array()
