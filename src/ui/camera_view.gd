extends CanvasLayer

const TEXT_FONT := preload("res://assets/fonts/FangZhengShuSongJianTi-1.ttf")
const LOOK_SPEED := 1.7
const DRAG_SENSITIVITY := 0.004
const ZOOM_STEP := 8.0
const ZOOM_KEY_SPEED := 45.0
const FOV_MIN := 30.0
const FOV_MAX := 110.0
const PITCH_MIN := -PI / 2.0
const PITCH_MAX := PI / 3.0

@onready var root:Control = $root
@onready var preview_margin:MarginContainer = $root/preview_margin
@onready var sub_viewport_container:SubViewportContainer = $root/preview_margin/sub_viewport_container
@onready var head:Node3D = $root/preview_margin/sub_viewport_container/sub_viewport/head
@onready var camera:Camera3D = $root/preview_margin/sub_viewport_container/sub_viewport/head/camera_3d
@onready var top_bar:ColorRect = $root/top_bar
@onready var controls:VBoxContainer = $root/controls
@onready var button_close:Button = $root/top_bar/margin_container_close/button_close
@onready var button_zoom_in:Button = $root/controls/margin_container_zoom_in/button_zoom_in
@onready var zoom_slider:VSlider = $root/controls/margin_container_slider/zoom_slider
@onready var button_zoom_out:Button = $root/controls/margin_container_zoom_out/button_zoom_out

var yaw:float = 0.0
var pitch:float = 0.0
var zoom_value:float = 50.0

func _ready() -> void:
	visible = false
	set_physics_process(false)
	get_viewport().size_changed.connect(_update_layout)
	button_close.pressed.connect(close)
	button_zoom_in.pressed.connect(_on_zoom_in_pressed)
	button_zoom_out.pressed.connect(_on_zoom_out_pressed)
	zoom_slider.value_changed.connect(zoom_camera)
	sub_viewport_container.gui_input.connect(_on_preview_gui_input)
	_prepare_button(button_close)
	_prepare_button(button_zoom_in)
	_prepare_button(button_zoom_out)
	_update_layout()
	zoom_camera(zoom_value)

func _physics_process(delta:float) -> void:
	var look_input:Vector2 = Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	if look_input.length_squared() > 0.0:
		_apply_look(Vector2(-look_input.x, -look_input.y) * LOOK_SPEED * delta)
	if Input.is_action_pressed("tab_right"):
		_zoom_by(ZOOM_KEY_SPEED * delta)
	if Input.is_action_pressed("tab_left"):
		_zoom_by(-ZOOM_KEY_SPEED * delta)

func open() -> void:
	_update_layout()
	set_physics_process(true)
	visible = true
	button_close.grab_focus()

func close() -> void:
	set_physics_process(false)
	visible = false
	get_viewport().set_input_as_handled()

func move_camera(_position:Vector3, _rotation:Vector3) -> void:
	head.global_position = _position
	head.global_rotation = _rotation
	pitch = head.global_rotation.x
	yaw = head.global_rotation.y
	_apply_look(Vector2.ZERO)

func zoom_camera(value:float) -> void:
	zoom_value = clampf(value, 0.0, 100.0)
	zoom_slider.set_value_no_signal(zoom_value)
	camera.fov = lerpf(FOV_MAX, FOV_MIN, zoom_value / 100.0)

func _on_zoom_in_pressed() -> void:
	_zoom_by(ZOOM_STEP)

func _on_zoom_out_pressed() -> void:
	_zoom_by(-ZOOM_STEP)

func _zoom_by(delta:float) -> void:
	zoom_camera(zoom_value + delta)

func _on_preview_gui_input(event:InputEvent) -> void:
	if event is InputEventMouseMotion:
		if !(event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		_apply_look(Vector2(-event.relative.x, event.relative.y) * DRAG_SENSITIVITY)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_STEP)
	elif event is InputEventScreenPinch:
		_zoom_by(event.relative * 0.05)

func _apply_look(delta:Vector2) -> void:
	yaw += delta.x
	pitch = clampf(pitch + delta.y, PITCH_MIN, PITCH_MAX)
	head.global_rotation = Vector3(pitch, yaw, 0.0)

func _prepare_button(button:Button) -> void:
	button.add_theme_font_override("font", TEXT_FONT)
	button.add_theme_font_size_override("font_size", 24)
	button.custom_minimum_size = Vector2(84.0, 52.0)

func _update_layout() -> void:
	var viewport_size:Vector2 = get_viewport().get_visible_rect().size
	var insets:Vector4 = UISafeArea.get_content_insets(get_viewport())
	var display_insets:Vector4 = UISafeArea.get_display_safe_insets(get_viewport())
	var side_margin:float = clampf(viewport_size.x * 0.025, 18.0, 32.0)
	var tool_height:float = clampf(viewport_size.y * 0.08, 64.0, 92.0)
	var top_height:float = maxf(insets.y, display_insets.y) + tool_height
	var controls_width:float = 84.0

	root.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	root.offset_left = 0.0
	root.offset_top = 0.0
	root.offset_right = 0.0
	root.offset_bottom = 0.0

	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE, false)
	top_bar.offset_left = 0.0
	top_bar.offset_top = 0.0
	top_bar.offset_right = 0.0
	top_bar.offset_bottom = top_height

	button_close.get_parent().offset_left = insets.x + side_margin
	button_close.get_parent().offset_top = maxf(insets.y, display_insets.y) + 6.0
	button_close.get_parent().offset_right = button_close.get_parent().offset_left + button_close.custom_minimum_size.x
	button_close.get_parent().offset_bottom = top_height

	preview_margin.set_anchors_preset(Control.PRESET_FULL_RECT, false)
	preview_margin.offset_left = insets.x + side_margin
	preview_margin.offset_top = top_height + side_margin
	preview_margin.offset_right = -(insets.z + side_margin + controls_width + side_margin)
	preview_margin.offset_bottom = -(insets.w + side_margin)

	controls.set_anchors_preset(Control.PRESET_TOP_RIGHT, false)
	controls.offset_left = -(insets.z + side_margin + controls_width)
	controls.offset_top = top_height + side_margin
	controls.offset_right = -(insets.z + side_margin)
	controls.offset_bottom = viewport_size.y - insets.w - side_margin
