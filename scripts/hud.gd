extends CanvasLayer

@onready var _scale_label: Label = $ScaleLabel


func _process(_delta: float) -> void:
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var view_width_km := get_viewport().get_visible_rect().size.x / zoom
	_scale_label.text = "View width: %s km" % _format_thousands(roundi(view_width_km))


func _format_thousands(value: int) -> String:
	var digits := str(value)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return result
