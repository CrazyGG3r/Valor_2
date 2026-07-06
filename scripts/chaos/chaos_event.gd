class_name ChaosEvent
extends Node3D
## Base class for all Chaos Mode hazards. Enforces the shared lifecycle:
##
##   begin() -> WARNING (telegraph visible, no damage)
##           -> ACTIVE  (_execute() runs the hazard)
##           -> _cleanup() + finished + queue_free
##
## Damage never fires during WARNING, so a hazard can never hit the player
## without a telegraph. Subclasses override the four virtuals below and add
## their visuals/hitboxes as children of this node, so freeing the event
## tears everything down.
##
## Hazard damage rides the existing Hitbox/Hurtbox pipeline with its own
## faction, so i-frames (dash!) and damage stats behave exactly like combat
## damage -- and hazards hit enemies as well as the player.

signal finished(event: ChaosEvent)

enum Phase { IDLE, WARNING, ACTIVE, DONE }

const HAZARD_FACTION := &"hazard"

## Stable identifier reported in hazard_info() for the AI observation layer.
@export var event_id := &"event"
@export var warning_duration := 1.5
@export var active_duration := 1.0
## Seconds before the director may pick this event again (counted from spawn).
## The director compresses this as run intensity ramps up.
@export var cooldown := 8.0

@export_group("Salvo")
## Instances the director spawns per pick at FULL intensity (a "shower").
## Scales up from 1 as the run's intensity curve climbs.
@export var salvo_max := 1
## Delay between consecutive instances within one salvo.
@export var salvo_stagger := 0.3

## Injected by the ChaosDirector before begin(); shared so a seeded run's
## entire event stream is reproducible for RL training.
var rng := RandomNumberGenerator.new()
var arena_center := Vector3.ZERO
var arena_half_extent := 24.0

var phase := Phase.IDLE
var _phase_time_left := 0.0


## Called by the director once the event is in the tree.
func begin() -> void:
	phase = Phase.WARNING
	_phase_time_left = warning_duration
	_start_warning()


## Aborts mid-lifecycle (run reset/end); still runs _cleanup and frees.
func cancel() -> void:
	if phase == Phase.DONE:
		return
	_finish()


func _physics_process(delta: float) -> void:
	match phase:
		Phase.WARNING:
			_warning_process(delta)
			_phase_time_left -= delta
			if _phase_time_left <= 0.0:
				phase = Phase.ACTIVE
				_phase_time_left = active_duration
				_execute()
		Phase.ACTIVE:
			_active_process(delta)
			_phase_time_left -= delta
			if _phase_time_left <= 0.0:
				_finish()


# --- virtuals (override in subclasses) ---------------------------------------


## Position the event, show the telegraph, and CREATE damage hitboxes here
## (inert) -- Area3D overlaps need physics frames to populate, so zones made
## during the warning are accurate by the time _execute() fires them.
func _start_warning() -> void:
	pass


## Per-frame during WARNING (animate the telegraph).
func _warning_process(_delta: float) -> void:
	pass


## Warning elapsed: apply the hazard (activate hitboxes, spawn visuals).
func _execute() -> void:
	pass


## Per-frame during ACTIVE (move beams, fade bolts, sink spikes).
func _active_process(_delta: float) -> void:
	pass


## Last hook before the node frees. Children are freed automatically; only
## undo external registrations here (groups, metas on other nodes).
func _cleanup() -> void:
	pass


# --- AI observation hook ------------------------------------------------------


## Self-description consumed by ChaosDirector.get_active_hazards() so the RL
## observation layer can encode hazards later. Subclasses merge in geometry
## (radius, sweep direction, ...).
func hazard_info() -> Dictionary:
	return {
		"type": String(event_id),
		"phase": "warning" if phase == Phase.WARNING else "active",
		"position": [global_position.x, global_position.z],
		"time_left": _phase_time_left,
	}


# --- shared helpers -----------------------------------------------------------


## Uniform random ground point in the arena square, `margin` in from the edge.
func pick_ground_point(margin := 0.0) -> Vector3:
	var extent := maxf(arena_half_extent - margin, 1.0)
	return arena_center + Vector3(
		rng.randf_range(-extent, extent), 0.0, rng.randf_range(-extent, extent))


## Hazard-faction Hitbox with the given shape, parented under `parent`
## (default: this event). Burst hitboxes stay inert until activate(duration).
func make_hitbox(shape: Shape3D, hit_damage: float, continuous := false,
		retrigger := 1.0, parent: Node3D = null) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.damage = hit_damage
	hitbox.faction = HAZARD_FACTION
	hitbox.continuous = continuous
	hitbox.retrigger_interval = retrigger
	var collision := CollisionShape3D.new()
	collision.shape = shape
	hitbox.add_child(collision)
	(parent if parent != null else self).add_child(hitbox)
	return hitbox


## Unshaded emissive material for hazard visuals; alpha < 1 enables blending.
static func make_glow_material(color: Color, alpha := 1.0, energy := 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _finish() -> void:
	phase = Phase.DONE
	_cleanup()
	finished.emit(self)
	queue_free()
