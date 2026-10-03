class_name Fleet
extends Node2D

## Owns the ships and which one is selected. N: launch a new ship into the home depot orbit.
## Tab / Shift+Tab: next / previous ship. Click a ship to select it.
## Only the selected ship takes keyboard and planner input and shows its full trajectory; the others
## show their current orbit faintly.

const PICK_RADIUS := 16.0
## Spacing between launched ships around the home depot orbit, so they don't overlap.
const SPAWN_SPACING_DEGREES := 40.0
const OTHER_ORBIT_COLOR := Color(0.6, 0.75, 0.95, 0.25)
const LABEL_COLOR := Color(0.85, 0.9, 1.0, 0.7)

@export var ship_scene: PackedScene
@export var home_body: CelestialBody
## Altitude of the orbit new ships start in, in km.
@export var home_altitude := 150.0
## Shows the selected ship's trajectory.
@export var trajectory_view: TrajectoryView
## Shows the other ships' orbits and every ship's name.
@export var fleet_view: TrajectoryView
@export var planner: ManeuverPlanner

var ships: Array[Ship] = []
var selected: Ship

## Follows the selected ship, so the camera can focus on it.
@onready var _selected_anchor: Node2D = $Ship


func _ready() -> void:
	spawn_ship()


func spawn_ship() -> Ship:
	var ship: Ship = ship_scene.instantiate()
	var number := ships.size() + 1
	ship.name = "Ship%d" % number
	ship.display_name = "Ship %d" % number
	ship.home_body = home_body
	ship.trajectory_view = trajectory_view
	ship.periapsis_altitude = home_altitude
	ship.apoapsis_altitude = home_altitude
	ship.spawn_angle = deg_to_rad(-SPAWN_SPACING_DEGREES * ships.size())
	add_child(ship)
	ships.append(ship)
	select(ship)
	return ship


func select(ship: Ship) -> void:
	if selected:
		selected.selected = false
		selected.maneuver_editing = false
	selected = ship
	ship.selected = true
	planner.select_ship(ship)


func cycle(step: int) -> void:
	select(ships[posmod(ships.find(selected) + step, ships.size())])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var ship := _ship_at(event.position)
		if ship:
			select(ship)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_TAB:
				cycle(-1 if event.shift_pressed else 1)
				get_viewport().set_input_as_handled()
			KEY_N:
				spawn_ship()


func _process(_delta: float) -> void:
	if selected:
		_selected_anchor.global_position = selected.global_position
	_update_fleet_view()


func _ship_at(screen_position: Vector2) -> Ship:
	var canvas_transform := get_viewport().get_canvas_transform()
	for ship in ships:
		if screen_position.distance_to(canvas_transform * ship.global_position) < PICK_RADIUS:
			return ship
	return null


func _update_fleet_view() -> void:
	var lines: Array[Dictionary] = []
	var markers: Array[Dictionary] = []
	for ship in ships:
		markers.append({
			"position": ship.global_position, "label": ship.display_name, "color": LABEL_COLOR,
			"dot": false, "offset": Vector2(16, -12),
		})
		if ship != selected and not ship.crashed:
			lines.append({"points": ship.current_orbit_points(), "color": OTHER_ORBIT_COLOR})
	fleet_view.show_contents(lines, markers, [])
