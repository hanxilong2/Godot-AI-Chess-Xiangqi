@tool
extends EditorScenePostImport

const OBJ_PATH := "res://assets/model/xiangqi/piece_set/象棋.obj"
const MARK_LIFT := 0.0015
const DEBUG_LOG_PATH := "res://tmp/xiangqi_overlay_import.log"

const WOOD_SURFACE_KEY := "wood"
const MARK_SURFACE_KEY := "mark"
const WOOD_MATERIAL_NAME := "材质.4"
const RED_MARK_MATERIAL_NAME := "材质.8"
const BLACK_MARK_MATERIAL_NAME := "材质.1"

const RED_MARK_COLOR := Color(0.80000001, 0.1236, 0.088, 1.0)
const BLACK_MARK_COLOR := Color(0.08, 0.08, 0.08, 1.0)

const PIECE_SPECS := {
	"仕_3": {"obj_name": "仕.3", "mark_color": RED_MARK_COLOR},
	"仕_2": {"obj_name": "仕.2", "mark_color": RED_MARK_COLOR},
	"仕_1": {"obj_name": "仕.1", "mark_color": RED_MARK_COLOR},
	"仕": {"obj_name": "仕", "mark_color": RED_MARK_COLOR},
	"相_1": {"obj_name": "相.1", "mark_color": RED_MARK_COLOR},
	"相": {"obj_name": "相", "mark_color": RED_MARK_COLOR},
	"马_1": {"obj_name": "马.1", "mark_color": RED_MARK_COLOR},
	"車_1": {"obj_name": "車.1", "mark_color": RED_MARK_COLOR},
	"马": {"obj_name": "马", "mark_color": RED_MARK_COLOR},
	"車": {"obj_name": "車", "mark_color": RED_MARK_COLOR},
	"車_1_2": {"obj_name": "車.1_1", "mark_color": RED_MARK_COLOR},
	"兵_3": {"obj_name": "兵.3", "mark_color": RED_MARK_COLOR},
	"兵_2": {"obj_name": "兵.2", "mark_color": RED_MARK_COLOR},
	"兵_1": {"obj_name": "兵.1", "mark_color": RED_MARK_COLOR},
	"兵": {"obj_name": "兵", "mark_color": RED_MARK_COLOR},
	"仕_4": {"obj_name": "仕.4", "mark_color": RED_MARK_COLOR},
	"炮_1": {"obj_name": "炮.1", "mark_color": BLACK_MARK_COLOR},
	"炮": {"obj_name": "炮", "mark_color": BLACK_MARK_COLOR},
	"卒": {"obj_name": "卒", "mark_color": BLACK_MARK_COLOR},
	"ma_1": {"obj_name": "ma.1", "mark_color": BLACK_MARK_COLOR},
	"向_1": {"obj_name": "向.1", "mark_color": BLACK_MARK_COLOR},
	"将": {"obj_name": "将", "mark_color": BLACK_MARK_COLOR},
	"士_1": {"obj_name": "士.1", "mark_color": BLACK_MARK_COLOR},
	"士": {"obj_name": "士", "mark_color": BLACK_MARK_COLOR},
	"向": {"obj_name": "向", "mark_color": BLACK_MARK_COLOR},
	"車_2": {"obj_name": "車_1", "mark_color": BLACK_MARK_COLOR},
	"ma": {"obj_name": "ma", "mark_color": BLACK_MARK_COLOR},
	"車_1_3": {"obj_name": "車.1_2", "mark_color": BLACK_MARK_COLOR},
}

static var _cached_piece_mesh_data: Dictionary = {}

func _post_import(scene: Node) -> Object:
	_log("start")
	_add_piece_letter_overlays(scene)
	_log("done")
	return scene

func _add_piece_letter_overlays(scene: Node) -> void:
	var piece_mesh_data := _load_piece_mesh_data()
	if piece_mesh_data.is_empty():
		_log("piece mesh data missing")
		return

	var overlay_count := 0
	for piece_name: String in PIECE_SPECS.keys():
		var piece := scene.find_child(piece_name, true, false) as MeshInstance3D
		if piece == null or piece.mesh == null:
			_log("piece missing: %s" % piece_name)
			continue

		for child: Node in piece.get_children():
			if child is MeshInstance3D and child.name.ends_with("_mark_overlay"):
				child.free()

		var piece_spec: Dictionary = PIECE_SPECS[piece_name]
		var obj_name := piece_spec["obj_name"] as String
		if not piece_mesh_data.has(obj_name):
			_log("obj data missing: %s" % obj_name)
			continue

		var overlay_mesh := _build_mark_overlay_mesh(
			piece.mesh.get_aabb(),
			piece_mesh_data[obj_name] as Dictionary
		)
		if overlay_mesh == null:
			_log("overlay mesh failed: %s" % piece_name)
			continue

		var overlay := MeshInstance3D.new()
		overlay.name = "%s_mark_overlay" % piece_name
		overlay.mesh = overlay_mesh
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.material_override = _create_mark_material(piece.get_active_material(0), piece_spec["mark_color"] as Color)
		piece.add_child(overlay)
		overlay.owner = scene
		overlay_count += 1

	_log("created overlays: %d" % overlay_count)

func _build_mark_overlay_mesh(target_aabb: AABB, piece_data: Dictionary) -> ArrayMesh:
	var source_aabb := _compute_vertex_aabb(piece_data[WOOD_SURFACE_KEY]["vertices"] as Array)
	var mark_vertices := piece_data[MARK_SURFACE_KEY]["vertices"] as Array
	if source_aabb.size == Vector3.ZERO or mark_vertices.is_empty():
		return null

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	var mapped_vertices := PackedVector3Array()
	for vertex: Vector3 in mark_vertices:
		mapped_vertices.append(_map_vertex_to_target_aabb(vertex, source_aabb, target_aabb))
	arrays[Mesh.ARRAY_VERTEX] = mapped_vertices

	var normals := PackedVector3Array()
	for normal: Vector3 in piece_data[MARK_SURFACE_KEY]["normals"]:
		normals.append(normal.normalized())
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(piece_data[MARK_SURFACE_KEY]["uvs"])

	var mesh := ArrayMesh.new()
	mesh.resource_local_to_scene = true
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _map_vertex_to_target_aabb(vertex: Vector3, source_aabb: AABB, target_aabb: AABB) -> Vector3:
	var x := _remap_axis(vertex.x, source_aabb.position.x, source_aabb.end.x, target_aabb.position.x, target_aabb.end.x)
	var y := _remap_axis(vertex.y, source_aabb.position.y, source_aabb.end.y, target_aabb.position.y, target_aabb.end.y) + MARK_LIFT
	var z := _remap_axis(vertex.z, source_aabb.position.z, source_aabb.end.z, target_aabb.position.z, target_aabb.end.z)
	return Vector3(x, y, z)

func _remap_axis(value: float, source_min: float, source_max: float, target_min: float, target_max: float) -> float:
	var source_size := source_max - source_min
	if is_zero_approx(source_size):
		return target_min
	var t := (value - source_min) / source_size
	return lerp(target_min, target_max, t)

func _compute_vertex_aabb(vertices: Array) -> AABB:
	if vertices.is_empty():
		return AABB()

	var aabb := AABB(vertices[0], Vector3.ZERO)
	for index: int in range(1, vertices.size()):
		aabb = aabb.expand(vertices[index])
	return aabb

func _load_piece_mesh_data() -> Dictionary:
	if not _cached_piece_mesh_data.is_empty():
		return _cached_piece_mesh_data

	var file := FileAccess.open(OBJ_PATH, FileAccess.READ)
	if file == null:
		_log("obj file missing")
		return {}

	var target_obj_names := {}
	for piece_spec: Dictionary in PIECE_SPECS.values():
		target_obj_names[piece_spec["obj_name"]] = true

	var vertices: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var normals: Array[Vector3] = []
	var piece_mesh_data := {}
	var current_obj_name := ""
	var current_material := ""

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("v "):
			vertices.append(_parse_vertex(line))
			continue
		if line.begins_with("vt "):
			uvs.append(_parse_uv(line))
			continue
		if line.begins_with("vn "):
			normals.append(_parse_normal(line))
			continue
		if line.begins_with("o "):
			current_obj_name = line.substr(2).strip_edges()
			if target_obj_names.has(current_obj_name) and not piece_mesh_data.has(current_obj_name):
				piece_mesh_data[current_obj_name] = _create_piece_surface_data()
			continue
		if line.begins_with("usemtl "):
			current_material = line.substr(7).strip_edges()
			continue
		if not line.begins_with("f ") or not target_obj_names.has(current_obj_name):
			continue

		var surface_key := _surface_key_for_material(current_material)
		if surface_key.is_empty():
			continue

		_append_face_to_surface(
			piece_mesh_data[current_obj_name][surface_key] as Dictionary,
			line.substr(2).split(" ", false),
			vertices,
			uvs,
			normals
		)

	_cached_piece_mesh_data = piece_mesh_data
	_log("loaded obj pieces: %d" % piece_mesh_data.size())
	return _cached_piece_mesh_data

func _create_piece_surface_data() -> Dictionary:
	return {
		WOOD_SURFACE_KEY: _create_surface_bucket(),
		MARK_SURFACE_KEY: _create_surface_bucket(),
	}

func _create_surface_bucket() -> Dictionary:
	return {
		"vertices": [],
		"normals": [],
		"uvs": [],
	}

func _surface_key_for_material(material_name: String) -> String:
	if material_name == WOOD_MATERIAL_NAME:
		return WOOD_SURFACE_KEY
	if material_name == RED_MARK_MATERIAL_NAME or material_name == BLACK_MARK_MATERIAL_NAME:
		return MARK_SURFACE_KEY
	return ""

func _append_face_to_surface(
	surface_data: Dictionary,
	face_tokens: Array[String],
	vertices: Array[Vector3],
	uvs: Array[Vector2],
	normals: Array[Vector3]
) -> void:
	if face_tokens.size() < 3:
		return

	var refs: Array[Dictionary] = []
	for face_token: String in face_tokens:
		refs.append(_parse_face_ref(face_token, vertices.size(), uvs.size(), normals.size()))

	for triangle_index: int in range(1, refs.size() - 1):
		_append_face_vertex(surface_data, refs[0], vertices, uvs, normals)
		_append_face_vertex(surface_data, refs[triangle_index], vertices, uvs, normals)
		_append_face_vertex(surface_data, refs[triangle_index + 1], vertices, uvs, normals)

func _append_face_vertex(
	surface_data: Dictionary,
	face_ref: Dictionary,
	vertices: Array[Vector3],
	uvs: Array[Vector2],
	normals: Array[Vector3]
) -> void:
	surface_data["vertices"].append(vertices[face_ref["vertex"]])

	if face_ref["normal"] >= 0:
		surface_data["normals"].append(normals[face_ref["normal"]])
	else:
		surface_data["normals"].append(Vector3.UP)

	if face_ref["uv"] >= 0:
		surface_data["uvs"].append(uvs[face_ref["uv"]])
	else:
		surface_data["uvs"].append(Vector2.ZERO)

func _parse_face_ref(face_token: String, vertex_count: int, uv_count: int, normal_count: int) -> Dictionary:
	var parts := face_token.split("/")
	var vertex_index := _resolve_obj_index(parts[0].to_int(), vertex_count)
	var uv_index := -1
	var normal_index := -1

	if parts.size() > 1 and not parts[1].is_empty():
		uv_index = _resolve_obj_index(parts[1].to_int(), uv_count)
	if parts.size() > 2 and not parts[2].is_empty():
		normal_index = _resolve_obj_index(parts[2].to_int(), normal_count)

	return {
		"vertex": vertex_index,
		"uv": uv_index,
		"normal": normal_index,
	}

func _resolve_obj_index(index: int, count: int) -> int:
	if index > 0:
		return index - 1
	if index < 0:
		return count + index
	return -1

func _parse_vertex(line: String) -> Vector3:
	var values := _parse_float_values(line)
	return Vector3(values[0], values[1], values[2])

func _parse_uv(line: String) -> Vector2:
	var values := _parse_float_values(line)
	return Vector2(values[0], values[1])

func _parse_normal(line: String) -> Vector3:
	var values := _parse_float_values(line)
	return Vector3(values[0], values[1], values[2])

func _parse_float_values(line: String) -> PackedFloat32Array:
	var parts := line.split(" ", false)
	var values := PackedFloat32Array()
	for index: int in range(1, parts.size()):
		values.append(parts[index].to_float())
	return values

func _create_mark_material(base_material: Material, color: Color) -> StandardMaterial3D:
	var material := _duplicate_standard_material(base_material)
	material.albedo_texture = null
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material

func _duplicate_standard_material(base_material: Material) -> StandardMaterial3D:
	var material: StandardMaterial3D
	if base_material is StandardMaterial3D:
		material = (base_material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
	else:
		material = StandardMaterial3D.new()
	material.resource_local_to_scene = true
	return material

func _log(message: String) -> void:
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(DEBUG_LOG_PATH) else FileAccess.WRITE
	var file := FileAccess.open(DEBUG_LOG_PATH, mode)
	if file == null:
		return
	file.seek_end()
	file.store_line(message)
