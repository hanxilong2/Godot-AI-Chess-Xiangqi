class_name UISafeArea
extends RefCounted

const DESIGN_ASPECT := 16.0 / 9.0

static func get_content_insets(viewport:Viewport, design_aspect:float = DESIGN_ASPECT) -> Vector4:
	var design_insets:Vector4 = get_design_insets(viewport, design_aspect)
	var display_insets:Vector4 = get_display_safe_insets(viewport)
	return Vector4(
		maxf(design_insets.x, display_insets.x),
		maxf(design_insets.y, display_insets.y),
		maxf(design_insets.z, display_insets.z),
		maxf(design_insets.w, display_insets.w)
	)

static func get_design_insets(viewport:Viewport, design_aspect:float = DESIGN_ASPECT) -> Vector4:
	var size:Vector2 = viewport.get_visible_rect().size
	if size.x <= 0.0 || size.y <= 0.0 || design_aspect <= 0.0:
		return Vector4.ZERO
	var viewport_aspect:float = size.x / size.y
	if is_equal_approx(viewport_aspect, design_aspect):
		return Vector4.ZERO
	if viewport_aspect < design_aspect:
		var content_height:float = size.x / design_aspect
		var inset_y:float = maxf((size.y - content_height) * 0.5, 0.0)
		return Vector4(0.0, inset_y, 0.0, inset_y)
	var content_width:float = size.y * design_aspect
	var inset_x:float = maxf((size.x - content_width) * 0.5, 0.0)
	return Vector4(inset_x, 0.0, inset_x, 0.0)

static func get_display_safe_insets(viewport:Viewport) -> Vector4:
	if DisplayServer.get_name() == "headless":
		return Vector4.ZERO
	if OS.get_name() != "Android" && OS.get_name() != "iOS":
		return Vector4.ZERO
	var window_size:Vector2i = DisplayServer.window_get_size()
	if window_size.x <= 0 || window_size.y <= 0:
		return Vector4.ZERO
	var safe_rect:Rect2i = DisplayServer.get_display_safe_area()
	if safe_rect.size.x <= 0 || safe_rect.size.y <= 0:
		return Vector4.ZERO
	var viewport_size:Vector2 = viewport.get_visible_rect().size
	var scale:Vector2 = Vector2(viewport_size.x / float(window_size.x), viewport_size.y / float(window_size.y))
	return Vector4(
		maxf(float(safe_rect.position.x), 0.0) * scale.x,
		maxf(float(safe_rect.position.y), 0.0) * scale.y,
		maxf(float(window_size.x - safe_rect.end.x), 0.0) * scale.x,
		maxf(float(window_size.y - safe_rect.end.y), 0.0) * scale.y
	)
