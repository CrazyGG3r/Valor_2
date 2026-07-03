class_name MeleeWeapon
extends Node3D
## Timed activation window for the child Hitbox. Damage and reach are tuned
## on the Hitbox and its collision shape in the scene; this node owns only
## the timing.

@export var cooldown := 0.6
@export var swing_duration := 0.2

@onready var hitbox: Hitbox = $Hitbox

var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func try_attack() -> bool:
	if _cooldown_left > 0.0:
		return false
	_cooldown_left = cooldown
	hitbox.activate(swing_duration)
	return true


## 0 = ready, 1 = just used. Fed to the HUD and AI observations.
func cooldown_fraction() -> float:
	return _cooldown_left / cooldown if cooldown > 0.0 else 0.0
