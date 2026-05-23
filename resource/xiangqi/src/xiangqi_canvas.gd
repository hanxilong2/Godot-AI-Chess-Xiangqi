extends Node3D
class_name XiangqiCanvas

@export var resolution: Vector2i = Vector2i(896, 1008)
@export var line_color: Color = Color(0.30, 0.17, 0.10, 0.70)
@export var river_color: Color = Color(0.57, 0.35, 0.18, 0.10)
@export var default_point_color: Color = Color(0.73, 0.18, 0.13, 0.70)

var layers: Dictionary = {}
var board_layer: BoardLayer = null

class BoardLayer extends Node2D:
	var resolution := Vector2.ZERO
	var line_color := Color.BLACK
	var river_color := Color(0, 0, 0, 0)

	func _draw() -> void:
		var cell_x := resolution.x / float(XiangqiConstants.BOARD_FILES)
		var cell_y := resolution.y / float(XiangqiConstants.BOARD_RANKS)
		var margin := Vector2(cell_x, cell_y) * 0.5
		var board_width := cell_x * float(XiangqiConstants.BOARD_FILES - 1)
		var board_height := cell_y * float(XiangqiConstants.BOARD_RANKS - 1)
		var river_top := margin.y + cell_y * 4.0
		var river_bottom := margin.y + cell_y * 5.0

		if river_color.a > 0.0:
			draw_rect(Rect2(Vector2(margin.x, river_top), Vector2(board_width, river_bottom - river_top)), river_color)

		for rank: int in XiangqiConstants.BOARD_RANKS:
			var y := margin.y + rank * cell_y
			draw_line(Vector2(margin.x, y), Vector2(margin.x + board_width, y), line_color, 2.0)

		for file: int in XiangqiConstants.BOARD_FILES:
			var x := margin.x + file * cell_x
			if file == 0 or file == XiangqiConstants.BOARD_FILES - 1:
				draw_line(Vector2(x, margin.y), Vector2(x, margin.y + board_height), line_color, 2.0)
			else:
				draw_line(Vector2(x, margin.y), Vector2(x, river_top), line_color, 2.0)
				draw_line(Vector2(x, river_bottom), Vector2(x, margin.y + board_height), line_color, 2.0)

		_draw_palace(3, 0, margin, cell_x, cell_y)
		_draw_palace(3, 7, margin, cell_x, cell_y)

	func _draw_palace(start_file: int, start_rank: int, margin: Vector2, cell_x: float, cell_y: float) -> void:
		var top_left := margin + Vector2(start_file * cell_x, start_rank * cell_y)
		var top_right := margin + Vector2((start_file + 2) * cell_x, start_rank * cell_y)
		var bottom_left := margin + Vector2(start_file * cell_x, (start_rank + 2) * cell_y)
		var bottom_right := margin + Vector2((start_file + 2) * cell_x, (start_rank + 2) * cell_y)
		draw_line(top_left, bottom_right, line_color, 2.0)
		draw_line(top_right, bottom_left, line_color, 2.0)

class PointLayer extends Node2D:
	var resolution := Vector2.ZERO
	var color := Color.RED
	var squares: Array = []
	var marker_scale := 0.18
	var outline_width := 4.0

	func _draw() -> void:
		var cell_x := resolution.x / float(XiangqiConstants.BOARD_FILES)
		var cell_y := resolution.y / float(XiangqiConstants.BOARD_RANKS)
		var margin := Vector2(cell_x, cell_y) * 0.5
		var radius := minf(cell_x, cell_y) * marker_scale
		var fill_color := color
		fill_color.a *= 0.72
		for square in squares:
			var index := XiangqiCoord.name_to_index(String(square))
			if index == -1:
				continue
			var coord := XiangqiCoord.from_index(index)
			var canvas_rank := XiangqiConstants.BOARD_RANKS - 1 - coord.y
			var marker_position := margin + Vector2(coord.x * cell_x, canvas_rank * cell_y)
			draw_circle(marker_position, radius, fill_color)
			draw_arc(marker_position, radius, 0.0, TAU, 32, color, outline_width)

func _ready() -> void:
	$sub_viewport.size = resolution
	board_layer = BoardLayer.new()
	board_layer.resolution = Vector2(float(resolution.x), float(resolution.y))
	board_layer.line_color = line_color
	board_layer.river_color = river_color
	$sub_viewport.add_child(board_layer)

func clear_layer(layer_name: String) -> void:
	if !layers.has(layer_name):
		return
	var layer := layers[layer_name] as Node
	layers.erase(layer_name)
	if is_instance_valid(layer):
		layer.free()

func draw_points(layer_name: String, squares: Array, color: Color = Color(0.73, 0.18, 0.13, 0.70)) -> void:
	clear_layer(layer_name)
	var layer := PointLayer.new()
	layer.resolution = Vector2(float(resolution.x), float(resolution.y))
	layer.color = color
	layer.squares = squares.duplicate()
	$sub_viewport.add_child(layer)
	layers[layer_name] = layer

func square_to_canvas(square_name: String) -> Vector2:
	var index := XiangqiCoord.name_to_index(square_name)
	if index == -1:
		return Vector2.ZERO
	var coord := XiangqiCoord.from_index(index)
	var cell_x := float(resolution.x) / float(XiangqiConstants.BOARD_FILES)
	var cell_y := float(resolution.y) / float(XiangqiConstants.BOARD_RANKS)
	var margin := Vector2(cell_x, cell_y) * 0.5
	var canvas_rank := XiangqiConstants.BOARD_RANKS - 1 - coord.y
	return margin + Vector2(coord.x * cell_x, canvas_rank * cell_y)
