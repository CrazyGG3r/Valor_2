class_name Hitbox
extends Area3D
## Damage-dealing area. Polls overlapping Hurtboxes each physics frame while
## active (polling avoids the missed-signal edge cases of toggling
## area_entered monitoring).
##
## Two modes:
##  - burst (continuous = false): inert until activate(duration); hits each
##    target at most once per activation. Melee swings, explosions.
##  - continuous = true: always on; re-hits each target every
##    retrigger_interval seconds. Contact damage.

const HURTBOX_LAYER := 8  # physics layer 4

@export var damage := 10.0
@export var faction := &"neutral"
@export var continuous := false
@export var retrigger_interval := 1.0

var _active := false
var _window_left := 0.0
# instance_id -> retrigger cooldown left (continuous) or a sentinel (burst)
var _targets: Dictionary = {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = HURTBOX_LAYER
	monitoring = true
	monitorable = false
	_active = continuous


## Burst mode: enable for `duration` seconds; each target is hit once.
func activate(duration: float) -> void:
	_active = true
	_window_left = duration
	_targets.clear()


func _physics_process(delta: float) -> void:
	if continuous:
		for key in _targets.keys():
			_targets[key] -= delta
			if _targets[key] <= 0.0:
				_targets.erase(key)
	elif _active:
		_window_left -= delta
		if _window_left <= 0.0:
			_active = false
			_targets.clear()
			return

	if not _active:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox == null or hurtbox.faction == faction:
			continue
		var key := hurtbox.get_instance_id()
		if _targets.has(key):
			continue
		if hurtbox.receive_hit(damage, self):
			_targets[key] = retrigger_interval if continuous else 1.0
