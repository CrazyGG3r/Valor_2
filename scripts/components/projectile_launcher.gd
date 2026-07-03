class_name ProjectileLauncher
extends Node3D
## Spawns projectiles on a cooldown. Aim direction comes from the caller, so
## a human, an AI, or an enemy brain can all fire it the same way.

@export var projectile_scene: PackedScene
@export var cooldown := 0.35
## Local-space spawn offset (-Z is forward).
@export var muzzle_offset := Vector3(0.0, 0.2, -0.8)
@export var faction := &"neutral"

var _cooldown_left := 0.0


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)


func try_fire(direction: Vector3) -> bool:
	if _cooldown_left > 0.0 or projectile_scene == null or direction == Vector3.ZERO:
		return false
	_cooldown_left = cooldown
	var projectile := projectile_scene.instantiate() as Projectile
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_transform * muzzle_offset
	projectile.launch(direction.normalized(), faction)
	return true


## 0 = ready, 1 = just used. Fed to the HUD and AI observations.
func cooldown_fraction() -> float:
	return _cooldown_left / cooldown if cooldown > 0.0 else 0.0
