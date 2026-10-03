class_name OrbitLine
extends Node2D

## Polyline that keeps the same on-screen thickness at any zoom level.

@export var color := Color(0.4, 0.85, 1.0, 0.7)
@export var screen_width := 1.5

var points := PackedVector2Array():
	set(value):
		points = value
		queue_redraw()

var _zoom := 0.0


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	if zoom != _zoom:
		_zoom = zoom
		queue_redraw()


func _draw() -> void:
	if _zoom <= 0.0 or points.size() < 2:
		return
	draw_polyline(points, color, screen_width / _zoom, true)
