extends Control
## First-person shotgun silhouette for the confront-the-visitor beat.

var _drawn := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func show_weapon() -> void:
	_drawn = true
	visible = true
	modulate.a = 0.0
	queue_redraw()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)

func hide_weapon() -> void:
	if not visible:
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	tw.finished.connect(func() -> void:
		visible = false
		_drawn = false
		queue_redraw())

func _draw() -> void:
	if not _drawn:
		return
	var w := size.x
	var h := size.y
	var metal := Color(0.12, 0.14, 0.11)
	var edge := Color(0.38, 0.50, 0.36, 0.95)
	var skin := Color(0.34, 0.31, 0.24)

	# stock and receiver
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.38, h * 1.05), Vector2(w * 0.47, h * 0.78),
		Vector2(w * 0.62, h * 0.78), Vector2(w * 0.74, h * 1.05),
	]), metal)
	draw_rect(Rect2(w * 0.44, h * 0.70, w * 0.20, h * 0.12), metal)

	# barrel toward the visitor
	draw_line(Vector2(w * 0.54, h * 0.76), Vector2(w * 0.50, h * 0.24), metal, 26.0)
	draw_line(Vector2(w * 0.54, h * 0.76), Vector2(w * 0.50, h * 0.24), edge, 3.0)
	draw_circle(Vector2(w * 0.50, h * 0.24), 9.0, edge)

	# hands on the grip
	draw_circle(Vector2(w * 0.47, h * 0.84), 36.0, skin)
	draw_circle(Vector2(w * 0.62, h * 0.88), 32.0, skin)
	draw_line(Vector2(w * 0.44, h * 0.80), Vector2(w * 0.55, h * 0.74), skin, 14.0)
	draw_line(Vector2(w * 0.61, h * 0.86), Vector2(w * 0.68, h * 0.94), skin, 12.0)
