class_name Ship
extends Node2D

## W/S: prograde/retrograde. A/D: radial in/out. Shift: 10% thrust. R: reset.

## Longest stretch of game time one thrust step covers, in seconds. Keeps burns accurate at high sim speed.
const MAX_BURN_STEP := 0.5
## How far out to draw escape trajectories, in km.
const ESCAPE_DRAW_RADIUS := 30000.0
const FINE_THRUST := 0.1

@export var central_body: CelestialBody
@export var orbit_line: OrbitLine
@export var periapsis_altitude := 100.0
@export var apoapsis_altitude := 400.0
## Engine acceleration in m/s².
@export var thrust_acceleration := 2.0
@export var color := Color(1.0, 0.85, 0.4)
@export var flame_color := Color(1.0, 0.5, 0.2)

var orbit: Orbit
var crashed := false
## Total speed change from burns so far, in m/s.
var delta_v_used := 0.0
## Current engine command as (prograde, radial out), each -1..1. Zero when the engine is off.
var thrust := Vector2.ZERO

var _last_time := 0.0
var _crash_position := Vector2.ZERO


func _ready() -> void:
	reset()


func reset() -> void:
	var periapsis := central_body.radius + periapsis_altitude
	var semi_major_axis := periapsis + (apoapsis_altitude - periapsis_altitude) / 2.0
	var speed := sqrt(central_body.mu * (2.0 / periapsis - 1.0 / semi_major_axis))
	orbit = Orbit.from_state(central_body.mu, Vector2(periapsis, 0.0), Vector2(0.0, -speed), Sim.time)
	crashed = false
	delta_v_used = 0.0
	_last_time = Sim.time


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset()


func _process(_delta: float) -> void:
	var now := Sim.time
	thrust = Vector2.ZERO if crashed else _read_thrust_input()
	if thrust != Vector2.ZERO:
		_burn(_last_time, now)
	_last_time = now

	var relative_position := orbit.position_at(now)
	if not crashed and relative_position.length() <= central_body.radius:
		crashed = true
		_crash_position = relative_position.normalized() * central_body.radius

	if crashed:
		global_position = central_body.global_position + _crash_position
	else:
		global_position = central_body.global_position + relative_position
		var velocity := orbit.velocity_at(now)
		var facing := velocity if thrust == Vector2.ZERO else _local_to_world(thrust, relative_position, velocity)
		rotation = facing.angle()

	scale = Vector2.ONE / get_viewport().get_canvas_transform().get_scale().x
	_update_orbit_line(now)
	queue_redraw()


func _draw() -> void:
	if thrust != Vector2.ZERO:
		var length := 6.0 + 10.0 * thrust.length()
		draw_colored_polygon(PackedVector2Array([
			Vector2(-4, 3.5), Vector2(-4 - length, 0), Vector2(-4, -3.5),
		]), flame_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(10, 0), Vector2(-7, 7), Vector2(-3, 0), Vector2(-7, -7),
	]), color)


func _read_thrust_input() -> Vector2:
	var command := Vector2(_key(KEY_W) - _key(KEY_S), _key(KEY_D) - _key(KEY_A))
	if command == Vector2.ZERO:
		return command
	return command.normalized() * (FINE_THRUST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)


func _key(keycode: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(keycode) else 0.0


func _burn(from_time: float, to_time: float) -> void:
	var steps := maxi(1, ceili((to_time - from_time) / MAX_BURN_STEP))
	var step := (to_time - from_time) / steps
	var acceleration := thrust_acceleration / 1000.0
	for i in steps:
		var t := from_time + step * (i + 0.5)
		var relative_position := orbit.position_at(t)
		var velocity := orbit.velocity_at(t)
		velocity += _local_to_world(thrust, relative_position, velocity) * acceleration * step
		orbit = Orbit.from_state(central_body.mu, relative_position, velocity, t)
	delta_v_used += thrust.length() * thrust_acceleration * (to_time - from_time)


## Converts (prograde, radial out) into a world direction for the given orbital state.
func _local_to_world(local: Vector2, relative_position: Vector2, velocity: Vector2) -> Vector2:
	var prograde := velocity.normalized()
	var radial_out := prograde.orthogonal()
	if radial_out.dot(relative_position) < 0.0:
		radial_out = -radial_out
	return prograde * local.x + radial_out * local.y


func _update_orbit_line(now: float) -> void:
	orbit_line.global_position = central_body.global_position
	orbit_line.visible = not crashed
	if crashed:
		return

	var radius := central_body.radius
	var nu_now := orbit.true_anomaly_at(now)
	var markers: Array[Dictionary] = []

	var surface_crossing := orbit.true_anomaly_at_radius(radius)
	if not is_nan(surface_crossing):
		var impact := -surface_crossing
		if orbit.is_elliptic() and impact < nu_now:
			impact += TAU
		if impact > nu_now:
			markers.append({"position": orbit.position_at_true_anomaly(impact), "label": "Impact"})
			orbit_line.points = orbit.sample_arc(nu_now, impact)
			orbit_line.markers = markers
			return

	if orbit.is_elliptic():
		orbit_line.points = orbit.sample_points()
		markers.append(_apsis_marker("Ap", orbit.apoapsis(), PI))
		markers.append(_apsis_marker("Pe", orbit.periapsis(), 0.0))
	else:
		var escape := orbit.true_anomaly_at_radius(ESCAPE_DRAW_RADIUS)
		orbit_line.points = orbit.sample_arc(nu_now, escape) if escape > nu_now else PackedVector2Array()
		if nu_now < 0.0:
			markers.append(_apsis_marker("Pe", orbit.periapsis(), 0.0))
	orbit_line.markers = markers


func _apsis_marker(label: String, distance: float, true_anomaly: float) -> Dictionary:
	return {
		"position": orbit.position_at_true_anomaly(true_anomaly),
		"label": "%s %d km" % [label, roundi(distance - central_body.radius)],
	}
