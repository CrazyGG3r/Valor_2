class_name Projectile
extends Area3D
## Straight-line projectile. Damages the first opposing Hurtbox it overlaps
## and despawns; also despawns on world geometry or when lifetime expires.
## Movement is simple translation -- fast enough and deterministic at these
## speeds/sizes (0.33 units per physics frame vs ~1 unit hurtbox radii).
##
## faction/direction are public so the AI ObservationBuilder can report
## incoming enemy shots; every projectile lives in the "projectiles" group.

const WORLD_LAYER := 1    # physics layer 1
const HURTBOX_LAYER := 8  # physics layer 4

@export var speed := 20.0
@export var damage := 10.0
@export var lifetime := 3.0

var faction := &"neutral"
var direction := Vector3.FORWARD

var _time_left := 0.0


func _ready() -> void:
	add_to_group(&"projectiles")
	collision_layer = 0
	collision_mask = WORLD_LAYER | HURTBOX_LAYER
	monitoring = true
	_time_left = lifetime
	body_entered.connect(func(_body: Node3D) -> void: queue_free())


func launch(new_direction: Vector3, new_faction: StringName) -> void:
	direction = new_direction
	faction = new_faction


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox != null and hurtbox.faction != faction \
				and hurtbox.receive_hit(damage, self):
			queue_free()
			return
