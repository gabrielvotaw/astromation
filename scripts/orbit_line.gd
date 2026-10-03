class_name OrbitLine
extends Node2D

## Polyline with labeled markers that keep the same on-screen size at any zoom level.

@export var color := Color(0.4, 0.85, 1.0, 0.7)
@export var screen_width := 1.5
@export var marker_font_size := 14

var points := PackedVector2Array():
	set(value):
		points = value
		queue_redraw()

## Each marker is {"position": Vector2, "label": String}.
var markers: Array[Dictionary] = []:
	set(value):
		markers = value
		queue_redraw()

var _zoom := 0.0


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	if zoom != _zoom:
		_zoom = zoom
		queue_redraw()


func _draw() -> void:
	if _zoom <= 0.0:
		return
	if points.size() >= 2:
		draw_polyline(points, color, screen_width / _zoom, true)

	var font := ThemeDB.fallback_font
	for marker in markers:
		draw_set_transform(marker.position, 0.0, Vector2.ONE / _zoom)
		draw_circle(Vector2.ZERO, 3.5, color, true, -1.0, true)
		draw_string(font, Vector2(7, -5), marker.label, HORIZONTAL_ALIGNMENT_LEFT, -1, marker_font_size, color)
	draw_set_transform(Vector2.ZERO)
