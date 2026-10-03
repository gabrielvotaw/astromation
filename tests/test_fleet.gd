extends RefCounted

var _failures := 0


## Runs every test and returns the number of failures.
func run(host: Node) -> int:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	host.add_child(main)
	var fleet: Fleet = main.get_node("Fleet")
	var planner: ManeuverPlanner = main.get_node("ManeuverPlanner")
	var haven_depot: Depot = main.get_node("HavenDepot")

	_test_starts_with_one_selected_ship(fleet, planner)
	_test_new_ship_is_selected_and_docked(fleet, planner, haven_depot)
	_test_ships_start_apart(fleet)
	_test_cycling_selection(fleet, planner)
	_test_maneuvers_belong_to_their_ship(fleet)

	host.remove_child(main)
	main.free()
	return _failures


func _test_starts_with_one_selected_ship(fleet: Fleet, planner: ManeuverPlanner) -> void:
	_check("starts with one ship", fleet.ships.size() == 1)
	_check("the first ship is selected", fleet.selected == fleet.ships[0] and fleet.ships[0].selected)
	_check("the planner works on the selected ship", planner.ship == fleet.selected)


func _test_new_ship_is_selected_and_docked(fleet: Fleet, planner: ManeuverPlanner, depot: Depot) -> void:
	var first := fleet.selected
	var second := fleet.spawn_ship()
	_check("a new ship is added", fleet.ships.size() == 2)
	_check("the new ship becomes the selection", fleet.selected == second and second.selected and not first.selected)
	_check("the planner follows the new selection", planner.ship == second)
	_check("the new ship starts in the home depot orbit", depot.is_docked(second))
	_check("ships get distinct names", first.display_name != second.display_name)


func _test_ships_start_apart(fleet: Fleet) -> void:
	var a := fleet.ships[0].orbit.position_at(Sim.time)
	var b := fleet.ships[1].orbit.position_at(Sim.time)
	_check("ships start at different points of the orbit", a.distance_to(b) > 100.0)


func _test_cycling_selection(fleet: Fleet, planner: ManeuverPlanner) -> void:
	fleet.select(fleet.ships[1])
	fleet.cycle(1)
	_check("cycling forward wraps to the first ship", fleet.selected == fleet.ships[0])
	fleet.cycle(-1)
	_check("cycling backward wraps to the last ship", fleet.selected == fleet.ships[1])
	_check("only one ship is selected at a time", fleet.ships.filter(func(s: Ship) -> bool: return s.selected).size() == 1)
	_check("the planner follows cycling", planner.ship == fleet.selected)


func _test_maneuvers_belong_to_their_ship(fleet: Fleet) -> void:
	var a := fleet.ships[0]
	var b := fleet.ships[1]
	a.add_maneuver(Sim.time + 500.0)
	_check("a maneuver added to one ship does not appear on another", a.maneuvers.size() == 1 and b.maneuvers.is_empty())


func _check(name: String, passed: bool) -> void:
	print(("PASS  " if passed else "FAIL  ") + name)
	if not passed:
		_failures += 1
