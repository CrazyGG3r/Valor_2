class_name Hurtbox
extends Area3D
## Damage-receiving area. Hitboxes and Projectiles call receive_hit(); the
## hurtbox forwards accepted hits to its HealthComponent and owns
## invulnerability frames, so i-frames behave identically no matter what the
## damage source is.

const HURTBOX_LAYER := 8  # physics layer 4

signal hit_received(amount: float, source: Node)

## Hits from a Hitbox/Projectile with the same faction are ignored.
@export var faction := &"neutral"
## Seconds of invulnerability granted after every accepted hit (i-frames).
@export var invulnerability_time := 0.0
## Auto-resolved to the parent's HealthComponent child when left empty.
@export var health: HealthComponent

var _invulnerable_left := 0.0


func _ready() -> void:
	collision_layer = HURTBOX_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	if health == null:
		for child in get_parent().get_children():
			if child is HealthComponent:
				health = child
				break
	if health == null:
		push_error("Hurtbox on '%s' found no HealthComponent." % get_parent().name)


func _physics_process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func set_invulnerable(duration: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left, duration)


## Returns true when the hit was applied (target alive, not invulnerable).
func receive_hit(amount: float, source: Node) -> bool:
	if is_invulnerable() or health == null or not health.is_alive():
		return false
	health.take_damage(amount, source)
	set_invulnerable(invulnerability_time)
	hit_received.emit(amount, source)
	return true
