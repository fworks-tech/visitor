extends Control
## One bar of the inspection light. Five lit bolts = five close looks.

var lit := true
var _poly: Polygon2D

func _init() -> void:
	custom_minimum_size = Vector2(18, 22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_poly = Polygon2D.new()
	_poly.polygon = PackedVector2Array([
		Vector2(10, 0), Vector2(2, 12), Vector2(8, 12),
		Vector2(5, 22), Vector2(16, 9), Vector2(9, 9),
	])
	_poly.antialiased = true
	add_child(_poly)
	set_lit(true)

func set_lit(value: bool) -> void:
	lit = value
	if _poly:
		_poly.color = Color(0.86, 0.96, 0.80) if lit else Color(0.16, 0.22, 0.16)
