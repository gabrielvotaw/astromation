extends RefCounted

var _failures := 0


## Runs every test and returns the number of failures.
func run(host: Node) -> int:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(main)
	var ship: Ship = main.get_node("Ship")

	_test_plan_applies_delta_v(ship)
	_test_executed_burn_matches_plan(ship)
	_test_long_burn_stays_close_to_plan(ship)

	host.remove_child(main)
	main.free()
	return _failures


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
