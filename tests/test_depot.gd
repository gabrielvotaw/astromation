extends RefCounted

var _failures := 0


## Runs every test and returns the number of failures.
func run(host: Node) -> int:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(main)
	var ship: Ship = main.get_node("Ship")
	var haven_depot: Depot = main.get_node("HavenDepot")
	var pale_depot: Depot = main.get_node("PaleDepot")
	var pale: CelestialBody = main.get_node("Pale")

	_test_ship_starts_docked_and_loads(ship, haven_depot)
	_test_loading_stops_at_capacity(ship, haven_depot)
	_test_eccentric_orbit_is_not_docked(ship, haven_depot)
	_test_burning_ship_is_not_docked(ship, haven_depot)
	_test_wrong_body_is_not_docked(ship, pale_depot)
	_test_unloads_at_demand_depot(ship, pale_depot, pale)

	host.remove_child(main)
	main.free()
	return _failures


func _test_ship_starts_docked_and_loads(ship: Ship, depot: Depot) -> void:
	ship.reset()
	depot.service(ship, 40.0)
	_check("ship starts docked at the Haven depot", ship.docked_at == depot)
	_check("docked ship loads crates over time", is_equal_approx(ship.cargo, depot.transfer_rate * 40.0))


func _test_loading_stops_at_capacity(ship: Ship, depot: Depot) -> void:
	ship.reset()
	depot.service(ship, 10000.0)
	_check("loading stops at capacity", ship.cargo == ship.capacity)


func _test_eccentric_orbit_is_not_docked(ship: Ship, depot: Depot) -> void:
	ship.reset()
	var mu := ship.reference_body.mu
	var periapsis := depot.orbit_radius()
	var apoapsis := periapsis + 2.0 * depot.tolerance
	var a := (periapsis + apoapsis) / 2.0
	ship.orbit = Orbit.from_state(mu, Vector2(periapsis, 0), Vector2(0, -sqrt(mu * (2.0 / periapsis - 1.0 / a))), Sim.time)
	depot.service(ship, 40.0)
	_check("orbit outside the docking zone does not dock", ship.docked_at == null and ship.cargo == 0.0)


func _test_burning_ship_is_not_docked(ship: Ship, depot: Depot) -> void:
	ship.reset()
	ship.engine_output = Vector2(1, 0)
	depot.service(ship, 40.0)
	ship.engine_output = Vector2.ZERO
	_check("ship with its engine on does not dock", ship.docked_at == null)


func _test_wrong_body_is_not_docked(ship: Ship, pale_depot: Depot) -> void:
	ship.reset()
	pale_depot.service(ship, 40.0)
	_check("ship around Haven does not dock at the Pale depot", ship.docked_at == null)


func _test_unloads_at_demand_depot(ship: Ship, depot: Depot, pale: CelestialBody) -> void:
	ship.reset()
	ship.cargo = 10.0
	ship.reference_body = pale
	var r := depot.orbit_radius()
	ship.orbit = Orbit.from_state(pale.mu, Vector2(r, 0), Vector2(0, -sqrt(pale.mu / r)), Sim.time)
	var before := depot.crates_moved
	depot.service(ship, 100.0)
	_check("docked at the demand depot", ship.docked_at == depot)
	_check("demand depot unloads crates", is_equal_approx(ship.cargo, 10.0 - depot.transfer_rate * 100.0))
	_check("demand depot counts delivered crates", is_equal_approx(depot.crates_moved - before, depot.transfer_rate * 100.0))
	depot.service(ship, 10000.0)
	_check("unloading stops at empty", ship.cargo == 0.0)


func _check(name: String, passed: bool) -> void:
	print(("PASS  " if passed else "FAIL  ") + name)
	if not passed:
		_failures += 1
