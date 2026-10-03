extends CanvasLayer

@export var ship: Ship

@onready var _info_label: Label = $InfoLabel


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var view_width_km := get_viewport().get_visible_rect().size.x / zoom
	var camera: Variant = get_viewport().get_camera_2d()
	var following := " (following %s)" % camera.focus_name() if camera.has_method("focus_name") else ""
	var lines := PackedStringArray([
		"View width: %s km%s" % [_format_thousands(roundi(view_width_km)), following],
		"Sim speed: %sx    T+ %s" % [String.num(Sim.speed), _format_duration(Sim.time)],
	])

	if ship and ship.crashed:
		lines.append("")
		lines.append("CRASHED on %s - press R to reset" % ship.reference_body.name)
	elif ship and ship.orbit:
		var orbit := ship.orbit
		var radius := ship.reference_body.radius
		var altitude := orbit.position_at(Sim.time).length() - radius
		var speed := orbit.velocity_at(Sim.time).length() * 1000.0
		var apoapsis := "escaping" if not orbit.is_elliptic() else "%s km" % _format_thousands(roundi(orbit.apoapsis() - radius))
		var period := "-" if not orbit.is_elliptic() else _format_duration(orbit.period())
		var engine := "off" if ship.thrust == Vector2.ZERO else "%d%%" % roundi(ship.thrust.length() * 100.0)
		lines.append("")
		lines.append("Orbiting: %s" % ship.reference_body.name)
		lines.append("Altitude: %s km    Speed: %s m/s" % [_format_thousands(roundi(altitude)), _format_thousands(roundi(speed))])
		lines.append("Apoapsis: %s    Periapsis: %s km    Period: %s" % [apoapsis, _format_thousands(roundi(orbit.periapsis() - radius)), period])
		lines.append("Engine: %s    Delta-v used: %s m/s" % [engine, _format_thousands(roundi(ship.delta_v_used))])

		var encounter := ship.next_encounter()
		if not encounter.is_empty():
			var approach: float = encounter.closest_approach
			var approach_text := "impact" if approach < 0.0 else "closest approach %s km" % _format_thousands(roundi(approach))
			lines.append("%s encounter in %s, %s" % [encounter.body.name, _format_duration(encounter.time - Sim.time), approach_text])

	_info_label.text = "\n".join(lines)


func _format_thousands(value: int) -> String:
	var digits := str(absi(value))
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return "-" + result if value < 0 else result


func _format_duration(seconds: float) -> String:
	var days := floori(seconds / 86400.0)
	var hours := floori(seconds / 3600.0) % 24
	var minutes := floori(seconds / 60.0) % 60
	var secs := floori(seconds) % 60
	if days > 0:
		return "%dd %02dh %02dm" % [days, hours, minutes]
	if hours > 0:
		return "%dh %02dm %02ds" % [hours, minutes, secs]
	return "%dm %02ds" % [minutes, secs]
