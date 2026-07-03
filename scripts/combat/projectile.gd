class_name Projectile
extends Area3D
## Straight-line projectile. Damages the first opposing Hurtbox it overlaps
## and despawns; also despawns on world geometry or when lifetime expires.
## Movement is simple translation -- fast enough and deterministic at these
## speeds/sizes (0.33 units per physics frame vs ~1 unit hurtbox radii).

const WORLD_LAYER := 1    # physics layer 1
const HURTBOX_LAYER := 8  # physics layer 4

@export var speed := 20.0
@export var damage := 10.0
@export var lifetime := 3.0

var _faction := &"neutral"
var _direction := Vector3.FORWARD
var _time_left := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = WORLD_LAYER | HURTBOX_LAYER
	monitoring = true
	_time_left = lifetime
	body_entered.connect(func(_body: Node3D) -> void: queue_free())


func launch(direction: Vector3, faction: StringName) -> void:
	_direction = direction
	_faction = faction


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox != null and hurtbox.faction != _faction \
				and hurtbox.receive_hit(damage, self):
			queue_free()
			return
