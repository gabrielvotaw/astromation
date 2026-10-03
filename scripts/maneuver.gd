class_name Maneuver
extends RefCounted

## A planned burn: at `time`, change velocity by `delta_v`, measured as (prograde, radial out) in m/s
## relative to the orbit at that moment.

var time: float
var delta_v := Vector2.ZERO

## Set when the burn starts.
var burning := false
## Delta-v still to apply during the burn, in m/s. Can go slightly negative for energy-guided burns.
var remaining := 0.0
## Mostly prograde/retrograde burns stop when the orbit reaches the planned energy rather than
## when the delta-v budget runs out. That compensates for long burns not being instant.
var energy_guided := false
## Planned orbital energy after the burn, in km²/s².
var target_energy := 0.0
