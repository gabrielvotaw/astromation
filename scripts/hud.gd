extends CanvasLayer

@export var ship: Ship

@onready var _info_label: Label = $InfoLabel


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var view_width_km := get_viewport().get_visible_rect().size.x / zoom
	var lines := PackedStringArray([
		"View width: %s km" % _format_thousands(roundi(view_width_km)),
		"Sim speed: %sx    T+ %s" % [String.num(Sim.speed), _format_duration(Sim.time)],
	])

	if ship and ship.orbit:
		var orbit := ship.orbit
		var radius := ship.central_body.radius
		var altitude := orbit.position_at(Sim.time).length() - radius
		var speed := orbit.velocity_at(Sim.time).length() * 1000.0
		var apoapsis := "escaping" if not orbit.is_elliptic() else "%s km" % _format_thousands(roundi(orbit.apoapsis() - radius))
		var period := "-" if not orbit.is_elliptic() else _format_duration(orbit.period())
		lines.append("")
		lines.append("Altitude: %s km    Speed: %s m/s" % [_format_thousands(roundi(altitude)), _format_thousands(roundi(speed))])
		lines.append("Apoapsis: %s    Periapsis: %s km    Period: %s" % [apoapsis, _format_thousands(roundi(orbit.periapsis() - radius)), period])

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
