class_name CelestialBody
extends Node2D

## Distances are in km (1 world unit = 1 km).

@export var radius := 600.0
## Gravitational parameter (G × mass), km³/s². 3531.6 gives 9.81 m/s² at a 600 km radius.
@export var mu := 3531.6
@export var atmosphere_height := 70.0
@export var surface_color := Color(0.22, 0.45, 0.7)
@export var atmosphere_color := Color(0.45, 0.7, 1.0, 0.15)


func _draw() -> void:
	if atmosphere_height > 0.0:
		draw_circle(Vector2.ZERO, radius + atmosphere_height, atmosphere_color, true, -1.0, true)
	draw_circle(Vector2.ZERO, radius, surface_color, true, -1.0, true)
