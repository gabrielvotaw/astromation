class_name Ship
extends Node2D

## W/S: prograde/retrograde. A/D: radial in/out. Shift: 10% thrust. R: reset.
## A planned maneuver is flown automatically, with the burn centered on the maneuver time.

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
## How visible the current path stays while a maneuver is planned.
const DIMMED_ALPHA := 0.3

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
## Like `prediction`, but starting at the planned maneuver with its delta-v applied. Empty if there is no plan.
var planned_prediction: Array[Dictionary] = []
var maneuver: Maneuver
## Set by the planner while the player is dragging the maneuver. Burns don't start mid-edit.
var maneuver_editing := false
var crashed := false
## Total speed change from burns so far, in m/s.
var delta_v_used := 0.0
## Manual engine command as (prograde, radial out), each -1..1. Zero when no keys are held.
var thrust := Vector2.ZERO
## World direction the engine pushed this frame, scaled by throttle. Zero when the engine is off.
var engine_output := Vector2.ZERO

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
	maneuver = null
	_last_time = Sim.time
	_predict(Sim.time)


func add_maneuver(time: float) -> void:
	maneuver = Maneuver.new()
	maneuver.time = time
	update_plan()


func remove_maneuver() -> void:
	maneuver = null
	update_plan()


## Recomputes planned_prediction. Call after changing the maneuver.
func update_plan() -> void:
	planned_prediction = []
	if maneuver == null or maneuver.burning or crashed or prediction.is_empty():
		return
	if maneuver.time > prediction[0].end_time:
		return
	var t := maneuver.time
	var relative_position := orbit.position_at(t)
	var velocity := orbit.velocity_at(t)
	velocity += _local_to_world(maneuver.delta_v / 1000.0, relative_position, velocity)
	planned_prediction = Trajectory.predict(reference_body, Orbit.from_state(reference_body.mu, relative_position, velocity, t), t)


## Where the maneuver sits and which way its prograde and radial-out axes point, in world space.
func maneuver_frame() -> Dictionary:
	var relative_position := orbit.position_at(maneuver.time)
	var velocity := orbit.velocity_at(maneuver.time)
	return {
		"position": reference_body.position_at(Sim.time) + relative_position,
		"prograde": _local_to_world(Vector2(1, 0), relative_position, velocity),
		"radial_out": _local_to_world(Vector2(0, 1), relative_position, velocity),
	}


## Game seconds needed to change speed by delta_v (m/s) at full thrust.
func burn_duration(delta_v: float) -> float:
	return delta_v / thrust_acceleration


## The next encounter in a prediction: {"body", "time", "closest_approach"} (closest approach is an
## altitude in km), or an empty Dictionary if there is none.
func next_encounter(patches: Array[Dictionary]) -> Dictionary:
	for i in patches.size() - 1:
		if patches[i].end == "encounter":
			var flyby: Dictionary = patches[i + 1]
			var body: CelestialBody = flyby.body
			return {
				"body": body,
				"time": patches[i].end_time,
				"closest_approach": flyby.orbit.periapsis() - body.radius,
			}
	return {}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset()


func _process(_delta: float) -> void:
	var now := Sim.time
	thrust = Vector2.ZERO if crashed else _read_thrust_input()
	engine_output = Vector2.ZERO

	var orbit_changed := false
	if thrust != Vector2.ZERO:
		var command := thrust
		_burn(_last_time, now, func(relative_position: Vector2, velocity: Vector2) -> Vector2:
			return _local_to_world(command, relative_position, velocity))
		delta_v_used += thrust.length() * thrust_acceleration * (now - _last_time)
		orbit_changed = true
	if maneuver and not crashed and _fly_maneuver(_last_time, now):
		orbit_changed = true
	if orbit_changed:
		_predict(now)
	_last_time = now

	if not crashed:
		_follow_prediction(now)
		if now >= _next_prediction_time:
			_predict(now)
		var relative_position := orbit.position_at(now)
		if relative_position.length() <= reference_body.radius:
			crashed = true
			maneuver = null
			planned_prediction = []
			_crash_position = relative_position.normalized() * reference_body.radius

	var body_position := reference_body.position_at(now)
	if crashed:
		engine_output = Vector2.ZERO
		global_position = body_position + _crash_position
	else:
		var relative_position := orbit.position_at(now)
		var velocity := orbit.velocity_at(now)
		global_position = body_position + relative_position
		if thrust != Vector2.ZERO:
			engine_output += _local_to_world(thrust, relative_position, velocity)
		rotation = (velocity if engine_output == Vector2.ZERO else engine_output).angle()

	scale = Vector2.ONE / get_viewport().get_canvas_transform().get_scale().x
	_update_trajectory_view(now)
	queue_redraw()


func _draw() -> void:
	if engine_output != Vector2.ZERO:
		var length := 6.0 + 10.0 * minf(engine_output.length(), 1.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-4, 3.5), Vector2(-4 - length, 0), Vector2(-4, -3.5),
		]), flame_color)
	draw_colored_polygon(PackedVector2Array([
		Vector2(10, 0), Vector2(-7, 7), Vector2(-3, 0), Vector2(-7, -7),
	]), color)


func _predict(time: float) -> void:
	prediction = Trajectory.predict(reference_body, orbit, time)
	_next_prediction_time = time + PREDICTION_REFRESH
	update_plan()


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


## Flies the part of the maneuver burn that falls between from_time and to_time.
## The burn holds its direction relative to prograde and radial (not fixed in space), which keeps
## long burns close to the plan. Returns true if the orbit changed.
func _fly_maneuver(from_time: float, to_time: float) -> bool:
	if not maneuver.burning:
		var start := maneuver.time - burn_duration(maneuver.delta_v.length()) / 2.0
		if to_time < start or maneuver_editing:
			return false
		_start_maneuver_burn()
		from_time = maxf(from_time, start)

	var local_direction := maneuver.delta_v.normalized()
	var direction := func(relative_position: Vector2, velocity: Vector2) -> Vector2:
		return _local_to_world(local_direction, relative_position, velocity)
	var steps := maxi(1, ceili((to_time - from_time) / MAX_BURN_STEP))
	var step := (to_time - from_time) / steps
	var burned := false
	for i in steps:
		if _maneuver_burn_done():
			break
		var duration := step if maneuver.energy_guided else minf(step, burn_duration(maneuver.remaining))
		var t := from_time + step * i
		_burn(t, t + duration, direction)
		maneuver.remaining -= duration * thrust_acceleration
		delta_v_used += duration * thrust_acceleration
		burned = true

	if burned:
		engine_output += direction.call(orbit.position_at(to_time), orbit.velocity_at(to_time))
	if _maneuver_burn_done():
		maneuver = null
	return burned


func _start_maneuver_burn() -> void:
	var t := maneuver.time
	var relative_position := orbit.position_at(t)
	var velocity := orbit.velocity_at(t)
	velocity += _local_to_world(maneuver.delta_v / 1000.0, relative_position, velocity)
	maneuver.target_energy = _orbital_energy(Orbit.from_state(reference_body.mu, relative_position, velocity, t))
	maneuver.energy_guided = absf(maneuver.delta_v.x) >= absf(maneuver.delta_v.y)
	maneuver.remaining = maneuver.delta_v.length()
	maneuver.burning = true
	planned_prediction = []


func _maneuver_burn_done() -> bool:
	if not maneuver.energy_guided:
		return maneuver.remaining <= 1e-6
	var energy := _orbital_energy(orbit)
	var reached := energy >= maneuver.target_energy if maneuver.delta_v.x > 0.0 else energy <= maneuver.target_energy
	var over_budget := maneuver.remaining <= -0.5 * maneuver.delta_v.length()
	return reached or over_budget


func _orbital_energy(of_orbit: Orbit) -> float:
	return -of_orbit.mu / (2.0 * of_orbit.semi_major_axis)


func _read_thrust_input() -> Vector2:
	var command := Vector2(_key(KEY_W) - _key(KEY_S), _key(KEY_D) - _key(KEY_A))
	if command == Vector2.ZERO:
		return command
	return command.normalized() * (FINE_THRUST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)


func _key(keycode: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(keycode) else 0.0


## Applies full thrust between the two times. `direction` maps (relative position, velocity) to a
## world-space thrust vector whose length is the throttle.
func _burn(from_time: float, to_time: float, direction: Callable) -> void:
	var steps := maxi(1, ceili((to_time - from_time) / MAX_BURN_STEP))
	var step := (to_time - from_time) / steps
	var acceleration := thrust_acceleration / 1000.0
	for i in steps:
		var t := from_time + step * (i + 0.5)
		var relative_position := orbit.position_at(t)
		var velocity := orbit.velocity_at(t)
		velocity += direction.call(relative_position, velocity) * acceleration * step
		orbit = Orbit.from_state(reference_body.mu, relative_position, velocity, t)


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

	if planned_prediction.is_empty():
		_add_patches(prediction, now, now, false, lines, markers, ghosts)
	else:
		_add_patches(prediction, now, now, true, lines, markers, ghosts)
		var points := _offset_points(_patch_points(orbit, now, maneuver.time), reference_body.position_at(now))
		lines.append({"points": points, "color": PATCH_COLORS[0]})
		_add_patches(planned_prediction, maneuver.time, now, false, lines, markers, ghosts)
	trajectory_view.show_contents(lines, markers, ghosts)


## Adds lines, markers and ghosts for a prediction. The first patch is drawn from first_start_time.
## Dimmed predictions get faded lines only.
func _add_patches(patches: Array[Dictionary], first_start_time: float, now: float, dimmed: bool,
		lines: Array[Dictionary], markers: Array[Dictionary], ghosts: Array[Dictionary]) -> void:
	for i in patches.size():
		var patch: Dictionary = patches[i]
		var body: CelestialBody = patch.body
		var patch_orbit: Orbit = patch.orbit
		var patch_color := PATCH_COLORS[i % PATCH_COLORS.size()]
		if dimmed:
			patch_color.a *= DIMMED_ALPHA
		var start_time: float = first_start_time if i == 0 else patch.start_time
		var end_time: float = patch.end_time

		# Future flybys are drawn around where the body will be at the encounter, not where it is now.
		var is_future_flyby := i > 0 and body.parent_body != null
		var anchor := body.position_at(patch.start_time if is_future_flyby else now)

		var points := _offset_points(_patch_points(patch_orbit, start_time, end_time), anchor)
		lines.append({"points": points, "color": patch_color})
		if dimmed:
			continue

		if is_future_flyby:
			ghosts.append({
				"position": anchor, "radius": body.radius,
				"sphere_of_influence": body.sphere_of_influence, "color": patch_color,
			})

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


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	for p in points.size():
		points[p] += offset
	return points


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
