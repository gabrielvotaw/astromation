extends RefCounted

var _failures := 0


## Runs every test and returns the number of failures.
func run(host: Node) -> int:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(main)
	var ship: Ship = main.get_node("Ship")
	var planner: ManeuverPlanner = main.get_node("ManeuverPlanner")

	_test_orbit_picking_is_stable(ship, planner)
	_test_plan_applies_delta_v(ship)
	_test_executed_burn_matches_plan(ship)
	_test_long_burn_stays_close_to_plan(ship)

	host.remove_child(main)
	main.free()
	return _failures


func _test_orbit_picking_is_stable(ship: Ship, planner: ManeuverPlanner) -> void:
	ship.reset()
	var start := Sim.time
	var anchor := ship.reference_body.position_at(start)
	var mouse := planner._to_screen(anchor + ship.orbit.position_at(start + ship.orbit.period() * 0.4)) + Vector2(3, 2)
	var picks: Array[Vector2] = []
	for i in 10:
		Sim.time = start + i * 3.7
		picks.append(planner._to_screen(anchor + ship.orbit.position_at(planner._pick_time(mouse, ManeuverPlanner.PICK_RADIUS))))
	Sim.time = start
	var spread := 0.0
	for pick in picks:
		spread = maxf(spread, pick.distance_to(picks[0]))
	_check("picked orbit point stays put while the ship moves (spread %.3f px)" % spread, spread < 0.05)


func _test_plan_applies_delta_v(ship: Ship) -> void:
	ship.reset()
	var t := Sim.time + ship.orbit.period() / 2.0
	ship.add_maneuver(t)
	ship.maneuver.delta_v = Vector2(100, 0)
	ship.update_plan()
	var planned: Orbit = ship.planned_prediction[0].orbit
	var expected_speed := ship.orbit.velocity_at(t).length() + 0.1
	_check("plan adds prograde delta-v at the maneuver time", absf(planned.velocity_at(t).length() - expected_speed) < 1e-4)
	_check("prograde burn at apoapsis raises periapsis", planned.periapsis() > ship.orbit.periapsis() + 50.0)


func _test_executed_burn_matches_plan(ship: Ship) -> void:
	ship.reset()
	var start := Sim.time
	ship.add_maneuver(start + ship.orbit.period() / 2.0)
	ship.maneuver.delta_v = Vector2(100, 20)
	ship.update_plan()
	var planned: Orbit = ship.planned_prediction[0].orbit

	var t := start
	while ship.maneuver != null and t < start + ship.orbit.period():
		ship._fly_maneuver(t, t + 1.0)
		t += 1.0
	_check("maneuver finishes and is removed", ship.maneuver == null)
	_check("maneuver uses about its planned delta-v", absf(ship.delta_v_used - Vector2(100, 20).length()) < 3.0)
	_check("finished burn lands close to the planned periapsis", absf(ship.orbit.periapsis() - planned.periapsis()) < 2.0)
	_check("finished burn lands close to the planned apoapsis", absf(ship.orbit.apoapsis() - planned.apoapsis()) < 2.0)


func _test_long_burn_stays_close_to_plan(ship: Ship) -> void:
	ship.reset()
	var start := Sim.time
	ship.add_maneuver(start + ship.orbit.period() / 2.0)
	ship.maneuver.delta_v = Vector2(830, 0)
	ship.update_plan()
	var planned: Orbit = ship.planned_prediction[0].orbit

	var t := start
	while ship.maneuver != null and t < start + 2.0 * ship.orbit.period():
		ship._fly_maneuver(t, t + 1.0)
		t += 1.0
	var error := absf(ship.orbit.apoapsis() - planned.apoapsis()) / planned.apoapsis()
	_check("long transfer burn lands within 5% of the planned apoapsis", error < 0.05)


func _check(name: String, passed: bool) -> void:
	print(("PASS  " if passed else "FAIL  ") + name)
	if not passed:
		_failures += 1
