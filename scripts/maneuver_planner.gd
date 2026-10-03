class_name ManeuverPlanner
extends Node2D

## Left-click the orbit to add a maneuver. Drag its handles to set the burn (Shift: fine control),
## drag the node to slide it along the orbit, X or Delete removes it.
## Must sit at the world origin: it draws in world coordinates.

## How close the mouse must be to grab something, in screen pixels.
const PICK_RADIUS := 10.0
## Distance from the node to each handle, in screen pixels.
const HANDLE_DISTANCE := 50.0
const PICK_SAMPLES := 360
## Dragging d pixels changes delta-v by |d| + DRAG_GROWTH·d² m/s, so small drags are precise and big drags are fast.
const DRAG_GROWTH := 0.02
const FINE_DRAG := 0.1
const NODE_COLOR := Color(1.0, 0.85, 0.4)
const FONT_SIZE := 13
const HANDLES := [
	{"axis": Vector2(1, 0), "label": "pro", "color": Color(0.55, 1.0, 0.4)},
	{"axis": Vector2(-1, 0), "label": "retro", "color": Color(0.55, 1.0, 0.4)},
	{"axis": Vector2(0, 1), "label": "out", "color": Color(0.35, 0.8, 1.0)},
	{"axis": Vector2(0, -1), "label": "in", "color": Color(0.35, 0.8, 1.0)},
]

enum Drag { NONE, NODE, HANDLE }

@export var ship: Ship

var _drag := Drag.NONE
var _drag_axis := Vector2.ZERO
var _drag_screen_direction := Vector2.ZERO
var _drag_start_mouse := Vector2.ZERO
var _drag_start_delta_v := Vector2.ZERO
var _hover_time := NAN


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_drag = Drag.NONE
		elif _start_drag(event.position):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		_continue_drag(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_X or event.physical_keycode == KEY_DELETE:
			ship.remove_maneuver()


func _process(_delta: float) -> void:
	ship.maneuver_editing = _drag != Drag.NONE
	_hover_time = NAN
	if ship.maneuver == null and not ship.crashed and _drag == Drag.NONE:
		_hover_time = _pick_time(get_viewport().get_mouse_position(), PICK_RADIUS)
	queue_redraw()


func _start_drag(mouse: Vector2) -> bool:
	if ship.crashed or (ship.maneuver and ship.maneuver.burning):
		return false

	if ship.maneuver:
		var frame := ship.maneuver_frame()
		var node_screen := _to_screen(frame.position)
		for handle in HANDLES:
			var direction := _handle_direction(frame, handle.axis)
			if mouse.distance_to(node_screen + direction * HANDLE_DISTANCE) < PICK_RADIUS:
				_drag = Drag.HANDLE
				_drag_axis = handle.axis
				_drag_screen_direction = direction
				_drag_start_mouse = mouse
				_drag_start_delta_v = ship.maneuver.delta_v
				return true
		if mouse.distance_to(node_screen) < PICK_RADIUS:
			_drag = Drag.NODE
			return true

	var time := _pick_time(mouse, PICK_RADIUS)
	if is_nan(time):
		return false
	if ship.maneuver:
		ship.maneuver.time = time
		ship.update_plan()
	else:
		ship.add_maneuver(time)
	_drag = Drag.NODE
	return true


func _continue_drag(mouse: Vector2) -> void:
	if ship.maneuver == null or ship.maneuver.burning:
		_drag = Drag.NONE
		return
	match _drag:
		Drag.NODE:
			var time := _pick_time(mouse, INF)
			if not is_nan(time):
				ship.maneuver.time = time
				ship.update_plan()
		Drag.HANDLE:
			var d := (mouse - _drag_start_mouse).dot(_drag_screen_direction)
			var amount := signf(d) * (absf(d) + DRAG_GROWTH * d * d)
			if Input.is_physical_key_pressed(KEY_SHIFT):
				amount *= FINE_DRAG
			ship.maneuver.delta_v = _drag_start_delta_v + _drag_axis * amount
			ship.update_plan()


## Time of the point on the ship's current orbit (before any encounter) closest to the mouse,
## or NAN if nothing is within max_distance screen pixels.
func _pick_time(mouse: Vector2, max_distance: float) -> float:
	if ship.prediction.is_empty():
		return NAN
	var orbit := ship.orbit
	var now := Sim.time
	var end_time: float = ship.prediction[0].end_time
	var from_nu := orbit.true_anomaly_at(now)
	var to_nu: float
	if is_inf(end_time):
		if orbit.is_elliptic():
			to_nu = from_nu + TAU
		else:
			to_nu = orbit.true_anomaly_at_radius(Trajectory.ESCAPE_RADIUS)
			if is_nan(to_nu) or to_nu <= from_nu:
				return NAN
	else:
		to_nu = orbit.true_anomaly_at(end_time)
		if orbit.is_elliptic() and to_nu < from_nu:
			to_nu += TAU

	var anchor := ship.reference_body.position_at(now)
	var best_nu := NAN
	var best_distance := max_distance
	for i in PICK_SAMPLES + 1:
		var nu := lerpf(from_nu, to_nu, float(i) / PICK_SAMPLES)
		var distance := mouse.distance_to(_to_screen(anchor + orbit.position_at_true_anomaly(nu)))
		if distance < best_distance:
			best_distance = distance
			best_nu = nu
	return NAN if is_nan(best_nu) else orbit.next_time_at_true_anomaly(best_nu, now)


func _handle_direction(frame: Dictionary, axis: Vector2) -> Vector2:
	return frame.prograde * axis.x + frame.radial_out * axis.y


func _to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position


func _draw() -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var font := ThemeDB.fallback_font

	if not is_nan(_hover_time):
		draw_set_transform(ship.reference_body.position_at(Sim.time) + ship.orbit.position_at(_hover_time), 0.0, Vector2.ONE / zoom)
		draw_circle(Vector2.ZERO, 6.0, NODE_COLOR, false, 1.5, true)
		draw_string(font, Vector2(10, -8), "Click to add maneuver", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, NODE_COLOR)

	if ship.maneuver and not ship.crashed:
		var maneuver := ship.maneuver
		var frame := ship.maneuver_frame()
		draw_set_transform(frame.position, 0.0, Vector2.ONE / zoom)
		if not maneuver.burning:
			for handle in HANDLES:
				var end: Vector2 = _handle_direction(frame, handle.axis) * HANDLE_DISTANCE
				var faded: Color = handle.color
				faded.a = 0.4
				draw_line(Vector2.ZERO, end, faded, 1.5, true)
				draw_circle(end, 6.0, handle.color, true, -1.0, true)
				draw_string(font, end + Vector2(8, 4), handle.label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2, handle.color)
		draw_circle(Vector2.ZERO, 7.0, NODE_COLOR, false, 2.0, true)
		var label := "%d m/s left" % roundi(maneuver.remaining) if maneuver.burning else "%d m/s" % roundi(maneuver.delta_v.length())
		draw_string(font, Vector2(10, -10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, NODE_COLOR)

	draw_set_transform(Vector2.ZERO)
