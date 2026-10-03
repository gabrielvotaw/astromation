class_name Ship
extends Node2D

@export var central_body: CelestialBody
@export var orbit_line: OrbitLine
@export var periapsis_altitude := 100.0
@export var apoapsis_altitude := 400.0
@export var color := Color(1.0, 0.85, 0.4)

var orbit: Orbit


func _ready() -> void:
	var periapsis := central_body.radius + periapsis_altitude
	var semi_major_axis := periapsis + (apoapsis_altitude - periapsis_altitude) / 2.0
	var speed := sqrt(central_body.mu * (2.0 / periapsis - 1.0 / semi_major_axis))
	orbit = Orbit.from_state(central_body.mu, Vector2(periapsis, 0.0), Vector2(0.0, -speed), Sim.time)
	orbit_line.points = orbit.sample_points()


func _process(_delta: float) -> void:
	var t := Sim.time
	global_position = central_body.global_position + orbit.position_at(t)
	rotation = orbit.velocity_at(t).angle()
	orbit_line.global_position = central_body.global_position
	scale = Vector2.ONE / get_viewport().get_canvas_transform().get_scale().x


func _draw() -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(10, 0), Vector2(-7, 7), Vector2(-3, 0), Vector2(-7, -7),
	]), color)
