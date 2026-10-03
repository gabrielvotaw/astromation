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
var crates_moved := 0

var _last_time := 0.0


func _ready() -> void:
	add_to_group("depots")
	_last_time = Sim.time


func orbit_radius() -> float:
	return body.radius + altitude


## Whether an orbit around `around` lies within this depot's docking zone.
func orbit_matches(around: CelestialBody, orbit: Orbit) -> bool:
	if around != body or not orbit.is_elliptic():
		return false
	var r := orbit_radius()
	return absf(orbit.periapsis() - r) <= tolerance and absf(orbit.apoapsis() - r) <= tolerance


func is_docked(ship: Ship) -> bool:
	return not ship.crashed and ship.engine_output == Vector2.ZERO and orbit_matches(ship.reference_body, ship.orbit)


## Docks or undocks the ship and moves crates for `game_seconds` of docked time. Crates move whole:
## one each time a full crate's worth of transfer time has built up.
func service(ship: Ship, game_seconds: float) -> void:
	if not is_docked(ship):
		if ship.docked_at == self:
			ship.docked_at = null
			ship.transfer_progress = 0.0
		return
	ship.docked_at = self
	ship.transfer_progress += transfer_rate * game_seconds
	while ship.transfer_progress >= 1.0 and _can_transfer(ship):
		ship.transfer_progress -= 1.0
		ship.cargo += 1 if kind == Kind.SUPPLY else -1
		crates_moved += 1
	if not _can_transfer(ship):
		ship.transfer_progress = 0.0


func _can_transfer(ship: Ship) -> bool:
	return ship.cargo < ship.capacity if kind == Kind.SUPPLY else ship.cargo > 0


func _process(_delta: float) -> void:
	var elapsed := Sim.time - _last_time
	_last_time = Sim.time
	for ship in get_tree().get_nodes_in_group("ships"):
		service(ship, elapsed)
	global_position = body.global_position
	queue_redraw()


func _draw() -> void:
	draw_ring(self, Vector2.ZERO, 1.0)


## Draws the depot ring, its docking zone and its label around `center`, in `canvas`'s coordinates.
## Call only from `canvas`'s _draw. Ghost copies at future encounters use a lower `opacity`.
func draw_ring(canvas: CanvasItem, center: Vector2, opacity: float) -> void:
	var zoom := canvas.get_viewport().get_canvas_transform().get_scale().x
	var r := orbit_radius()
	var line_color := color
	line_color.a *= opacity
	var zone := line_color
	zone.a = 0.07 * opacity
	_draw_zone(canvas, center, r - tolerance, r + tolerance, zone)
	var dashes := 72
	for i in dashes:
		if i % 2 == 0:
			canvas.draw_arc(center, r, TAU * i / dashes, TAU * (i + 1) / dashes, 6, line_color, 2.0 / zoom, true)
	canvas.draw_set_transform(center + Vector2(0, -r), 0.0, Vector2.ONE / zoom)
	canvas.draw_string(ThemeDB.fallback_font, Vector2(8, -8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, line_color)
	canvas.draw_set_transform(Vector2.ZERO)


## A closed band of triangles. A thick translucent draw_arc shows a seam where its two ends overlap.
static func _draw_zone(canvas: CanvasItem, center: Vector2, inner: float, outer: float, zone_color: Color) -> void:
	var segments := 256
	var points := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments:
		var direction := Vector2.from_angle(TAU * i / segments)
		points.append(center + direction * inner)
		points.append(center + direction * outer)
		var next := (i + 1) % segments
		indices.append_array([2 * i, 2 * i + 1, 2 * next + 1, 2 * i, 2 * next + 1, 2 * next])
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(zone_color)
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors)
