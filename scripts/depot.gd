class_name Depot
extends Node2D

## A parking orbit where ships load or unload crates. A ship is docked when its orbit around `body`
## is within `tolerance` km of the depot orbit at both apoapsis and periapsis, with its engine off.
## No rendezvous: the depot is the whole orbit, not a point on it.

enum Kind { SUPPLY, DEMAND }

@export var body: CelestialBody
## Height of the depot orbit above the surface, in km.
@export var altitude := 150.0
@export var kind := Kind.SUPPLY
## How far (km) apoapsis and periapsis may be from the depot orbit while docked.
@export var tolerance := 50.0
## Crates moved per game second while a ship is docked.
@export var transfer_rate := 0.05
@export var label := "Depot"
@export var color := Color(0.45, 1.0, 0.6, 0.7)

## Crates handed out (supply) or received (demand) so far.
var crates_moved := 0.0

var _last_time := 0.0


func _ready() -> void:
	add_to_group("depots")
	_last_time = Sim.time


func orbit_radius() -> float:
	return body.radius + altitude


func is_docked(ship: Ship) -> bool:
	if ship.crashed or ship.reference_body != body or ship.engine_output != Vector2.ZERO:
		return false
	if not ship.orbit.is_elliptic():
		return false
	var r := orbit_radius()
	return absf(ship.orbit.periapsis() - r) <= tolerance and absf(ship.orbit.apoapsis() - r) <= tolerance


## Docks or undocks the ship and moves crates for `game_seconds` of docked time.
func service(ship: Ship, game_seconds: float) -> void:
	if not is_docked(ship):
		if ship.docked_at == self:
			ship.docked_at = null
		return
	ship.docked_at = self
	var amount := transfer_rate * game_seconds
	if kind == Kind.SUPPLY:
		amount = minf(amount, ship.capacity - ship.cargo)
		ship.cargo += amount
	else:
		amount = minf(amount, ship.cargo)
		ship.cargo -= amount
	crates_moved += amount


func _process(_delta: float) -> void:
	var elapsed := Sim.time - _last_time
	_last_time = Sim.time
	for ship in get_tree().get_nodes_in_group("ships"):
		service(ship, elapsed)
	global_position = body.global_position
	queue_redraw()


func _draw() -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var r := orbit_radius()
	var zone := color
	zone.a = 0.07
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 128, zone, 2.0 * tolerance, true)
	var dashes := 72
	for i in dashes:
		if i % 2 == 0:
			draw_arc(Vector2.ZERO, r, TAU * i / dashes, TAU * (i + 1) / dashes, 6, color, 2.0 / zoom, true)
	draw_set_transform(Vector2(0, -r), 0.0, Vector2.ONE / zoom)
	draw_string(ThemeDB.fallback_font, Vector2(8, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)
	draw_set_transform(Vector2.ZERO)
