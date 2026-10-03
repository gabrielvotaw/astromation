class_name Ship
extends Node2D

## W/S: prograde/retrograde. A/D: radial in/out. Shift: 10% thrust. R: reset.

## Longest stretch of game time one thrust step covers, in seconds. Keeps burns accurate at high sim speed.
const MAX_BURN_STEP := 0.5
const FINE_THRUST := 0.1
## Game seconds between prediction refreshes while coasting, so the encounter search window keeps moving forward.
const PREDICTION_REFRESH := 100.0
const PATCH_COLORS: Array[Color] = [
	Color(0.4, 0.85, 1.0, 0.75),
	Color(1.0, 0.7, 0.3, 0.85),
	Color(0.8, 0.55, 1.0, 0.75),
]

@export var home_body: CelestialBody
@export var trajectory_view: TrajectoryView
@export var periapsis_altitude := 100.0
@export var apoapsis_altitude := 400.0
## Engine acceleration in m/s².
@export var thrust_acceleration := 2.0
@export var color := Color(1.0, 0.85, 0.4)
@export var flame_color := Color(1.0, 0.5, 0.2)

## The body whose gravity the ship currently feels. `orbit` is relative to it.
var reference_body: CelestialBody
var orbit: Orbit
## See Trajectory.predict for the patch format.
var prediction: Array[Dictionary] = []
var crashed := false
## Total speed change from burns so far, in m/s.
var delta_v_used := 0.0
## Current engine command as (prograde, radial out), each -1..1. Zero when the engine is off.
var thrust := Vector2.ZERO

var _last_time := 0.0
var _next_prediction_time := 0.0
var _crash_position := Vector2.ZERO


func _ready() -> void:
	reset()


func reset() -> void:
	reference_body = home_body
	var periapsis := home_body.radius + periapsis_altitude
	var semi_major_axis := periapsis + (apoapsis_altitude - periapsis_altitude) / 2.0
	var speed := sqrt(home_body.mu * (2.0 / periapsis - 1.0 / semi_major_axis))
	orbit = Orbit.from_state(home_body.mu, Vector2(periapsis, 0.0), Vector2(0.0, -speed), Sim.time)
	crashed = false
	delta_v_used = 0.0
	_last_time = Sim.time
	_predict(Sim.time)


## The next predicted encounter: {"body", "time", "closest_approach"} (closest approach is an altitude in km),
## or an empty Dictionary if there is none.
func next_encounter() -> Dictionary:
	for i in prediction.size() - 1:
		if prediction[i].end == "encounter":
			var flyby: Dictionary = prediction[i + 1]
			var body: CelestialBody = flyby.body
			return {
				"body": body,
				"time": prediction[i].end_time,
				"closest_approach": flyby.orbit.periapsis() - body.radius,
			}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset()


func _process(_delta: float) -> void:
	var now := Sim.time
	thrust = Vector2.ZERO if crashed else _read_thrust_input()
	if thrust != Vector2.ZERO:
		_burn(_last_time, now)
		_predict(now)
	_last_time = now

	if not crashed:
		_follow_prediction(now)
		if now >= _next_prediction_time:
			_predict(now)
		var relative_position := orbit.position_at(now)
		if relative_position.length() <= reference_body.radius:
			crashed = true
			_crash_position = relative_position.normalized() * reference_body.radius

	var body_position := reference_body.position_at(now)
	if crashed:
		global_position = body_position + _crash_position
	else:
		var relative_position := orbit.position_at(now)
		var velocity := orbit.velocity_at(now)
		global_position = body_position + relative_position
		var facing := velocity if thrust == Vector2.ZERO else _local_to_world(thrust, relative_position, velocity)
		rotation = facing.angle()

	scale = Vector2.ONE / get_viewport().get_canvas_transform().get_scale().x
	_update_trajectory_view(now)
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


func _predict(time: float) -> void:
	prediction = Trajectory.predict(reference_body, orbit, time)
	_next_prediction_time = time + PREDICTION_REFRESH


## Switches gravity at exactly the moments the prediction says, so the ship always does what was drawn.
func _follow_prediction(now: float) -> void:
	for i in 8:
		if prediction.is_empty():
			return
		var patch: Dictionary = prediction[0]
		if patch.next_body == null or patch.end_time > now:
			return
		orbit = Trajectory.change_frame(orbit, reference_body, patch.next_body, patch.end_time)
		reference_body = patch.next_body
		_predict(patch.end_time)


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
		orbit = Orbit.from_state(reference_body.mu, relative_position, velocity, t)
	delta_v_used += thrust.length() * thrust_acceleration * (to_time - from_time)


## Converts (prograde, radial out) into a world direction for the given orbital state.
func _local_to_world(local: Vector2, relative_position: Vector2, velocity: Vector2) -> Vector2:
	var prograde := velocity.normalized()
	var radial_out := prograde.orthogonal()
	if radial_out.dot(relative_position) < 0.0:
		radial_out = -radial_out
	return prograde * local.x + radial_out * local.y


func _update_trajectory_view(now: float) -> void:
	var lines: Array[Dictionary] = []
	var markers: Array[Dictionary] = []
	var ghosts: Array[Dictionary] = []
	if crashed:
		trajectory_view.show_contents(lines, markers, ghosts)
		return

	for i in prediction.size():
		var patch: Dictionary = prediction[i]
		var body: CelestialBody = patch.body
		var patch_orbit: Orbit = patch.orbit
		var patch_color := PATCH_COLORS[i % PATCH_COLORS.size()]
		var start_time: float = now if i == 0 else patch.start_time
		var end_time: float = patch.end_time

		# Future flybys are drawn around where the body will be at the encounter, not where it is now.
		var is_future_flyby := i > 0 and body.parent_body != null
		var anchor := body.position_at(patch.start_time if is_future_flyby else now)
		if is_future_flyby:
			ghosts.append({
				"position": anchor, "radius": body.radius,
				"sphere_of_influence": body.sphere_of_influence, "color": patch_color,
			})

		var points := _patch_points(patch_orbit, start_time, end_time)
		for p in points.size():
			points[p] += anchor
		lines.append({"points": points, "color": patch_color})

		for apsis in [[0.0, "Pe"], [PI, "Ap"]]:
			if apsis[1] == "Ap" and not patch_orbit.is_elliptic():
				continue
			if patch_orbit.next_time_at_true_anomaly(apsis[0], start_time) < end_time:
				var distance := patch_orbit.position_at_true_anomaly(apsis[0]).length()
				markers.append({
					"position": anchor + patch_orbit.position_at_true_anomaly(apsis[0]),
					"label": "%s %d km" % [apsis[1], roundi(distance - body.radius)],
					"color": patch_color,
				})

		var end_label := ""
		match patch.end:
			"impact":
				end_label = "Impact"
			"encounter":
				end_label = "%s encounter" % patch.next_body.name
			"escape":
				end_label = "Leaving %s" % body.name
		if end_label != "":
			markers.append({"position": anchor + patch_orbit.position_at(end_time), "label": end_label, "color": patch_color})

	trajectory_view.show_contents(lines, markers, ghosts)


func _patch_points(patch_orbit: Orbit, from_time: float, to_time: float) -> PackedVector2Array:
	var from_nu := patch_orbit.true_anomaly_at(from_time)
	if is_inf(to_time):
		if patch_orbit.is_elliptic():
			return patch_orbit.sample_points()
		var escape_nu := patch_orbit.true_anomaly_at_radius(Trajectory.ESCAPE_RADIUS)
		return patch_orbit.sample_arc(from_nu, escape_nu) if escape_nu > from_nu else PackedVector2Array()
	if patch_orbit.is_elliptic() and to_time - from_time >= patch_orbit.period():
		return patch_orbit.sample_points()
	var to_nu := patch_orbit.true_anomaly_at(to_time)
	if patch_orbit.is_elliptic() and to_nu < from_nu:
		to_nu += TAU
	return patch_orbit.sample_arc(from_nu, to_nu)
