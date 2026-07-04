class_name Player
extends CharacterBody3D
## Physical player body. Knows nothing about WHERE its commands come from --
## it only reads the InputProvider contract, so human and AI control are
## interchangeable. Combat is delegated to child components; only dash lives
## here because it is a movement state.

@export_group("Movement")
@export var speed := 5.0
@export var jump_velocity := 4.5
@export var gravity := 9.8

@export_group("Dash")
@export var dash_speed := 14.0
@export var dash_duration := 0.2
@export var dash_cooldown := 1.2

## Falls back to the first InputProvider child if left unassigned.
@export var input_provider: InputProvider

@onready var health: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var melee_weapon: MeleeWeapon = $MeleeWeapon
@onready var projectile_launcher: ProjectileLauncher = $ProjectileLauncher
@onready var level_system: LevelSystem = $LevelSystem

var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_direction := Vector3.ZERO
var _base_stats: Dictionary


func _ready() -> void:
	if input_provider == null:
		for child in get_children():
			if child is InputProvider:
				input_provider = child
				break
	if input_provider == null:
		push_error("Player has no InputProvider; it cannot be controlled.")
	_base_stats = {
		"speed": speed,
		"dash_cooldown": dash_cooldown,
		"melee_cooldown": melee_weapon.cooldown,
		"melee_damage": melee_weapon.hitbox.damage,
		"shoot_cooldown": projectile_launcher.cooldown,
		"projectile_damage": projectile_launcher.damage,
		"max_health": health.max_health,
	}


## Restores scene-authored stats. Called at run start so upgrades from the
## previous run don't leak into the next one.
func reset_stats() -> void:
	speed = _base_stats["speed"]
	dash_cooldown = _base_stats["dash_cooldown"]
	melee_weapon.cooldown = _base_stats["melee_cooldown"]
	melee_weapon.hitbox.damage = _base_stats["melee_damage"]
	projectile_launcher.cooldown = _base_stats["shoot_cooldown"]
	projectile_launcher.damage = _base_stats["projectile_damage"]
	health.max_health = _base_stats["max_health"]


## Applies a data-driven upgrade to this body's stats.
func apply_upgrade(upgrade: Upgrade) -> void:
	match upgrade.stat:
		&"move_speed":
			speed = _apply_operation(speed, upgrade)
		&"melee_damage":
			melee_weapon.hitbox.damage = _apply_operation(melee_weapon.hitbox.damage, upgrade)
		&"projectile_damage":
			projectile_launcher.damage = _apply_operation(projectile_launcher.damage, upgrade)
		&"attack_speed":
			melee_weapon.cooldown = _apply_operation(melee_weapon.cooldown, upgrade)
			projectile_launcher.cooldown = _apply_operation(projectile_launcher.cooldown, upgrade)
		&"dash_cooldown":
			dash_cooldown = _apply_operation(dash_cooldown, upgrade)
		&"max_health":
			var previous := health.max_health
			health.max_health = _apply_operation(previous, upgrade)
			health.heal(health.max_health - previous)
		_:
			push_warning("Unknown upgrade stat: %s" % upgrade.stat)


func _apply_operation(current: float, upgrade: Upgrade) -> float:
	if upgrade.operation == Upgrade.Operation.ADD:
		return current + upgrade.value
	return current * upgrade.value


func _physics_process(delta: float) -> void:
	if input_provider == null:
		return
	input_provider.poll()

	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_dash_time_left = maxf(_dash_time_left - delta, 0.0)

	if not health.is_alive():
		_process_dead(delta)
		return

	# look_delta.y (pitch) stays unused until the first-person camera
	# milestone; the body only yaws.
	rotate_y(-input_provider.get_look_delta().x)

	if is_on_floor():
		velocity.y = 0.0
		if input_provider.is_just_pressed(InputProvider.ACTION_JUMP):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	var move := input_provider.get_move_vector()
	var direction := global_transform.basis * Vector3(move.x, 0.0, move.y)

	if input_provider.is_just_pressed(InputProvider.ACTION_DASH):
		_try_dash(direction)

	if _dash_time_left > 0.0:
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
	elif direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	# Held buttons auto-repeat, gated by each component's cooldown. Works the
	# same for a held mouse button and an AI holding the action at true.
	if input_provider.is_pressed(InputProvider.ACTION_ATTACK):
		melee_weapon.try_attack()
	if input_provider.is_pressed(InputProvider.ACTION_SHOOT):
		var forward := -global_transform.basis.z
		forward.y = 0.0
		projectile_launcher.try_fire(forward.normalized())

	move_and_slide()


## Cooldown fractions (0 = ready, 1 = just used) for HUD and AI observations.
func get_cooldowns() -> Dictionary:
	return {
		"melee": melee_weapon.cooldown_fraction(),
		"shoot": projectile_launcher.cooldown_fraction(),
		"dash": _dash_cooldown_left / dash_cooldown if dash_cooldown > 0.0 else 0.0,
	}


func _try_dash(move_direction: Vector3) -> void:
	if _dash_cooldown_left > 0.0 or _dash_time_left > 0.0:
		return
	_dash_direction = move_direction.normalized()
	if _dash_direction == Vector3.ZERO:
		_dash_direction = -global_transform.basis.z  # idle dash goes forward
	_dash_time_left = dash_duration
	_dash_cooldown_left = dash_cooldown
	hurtbox.set_invulnerable(dash_duration + 0.05)


func _process_dead(delta: float) -> void:
	# Ignore all commands until the run resets; just settle physically.
	if not is_on_floor():
		velocity.y -= gravity * delta
	velocity.x = move_toward(velocity.x, 0.0, speed)
	velocity.z = move_toward(velocity.z, 0.0, speed)
	move_and_slide()
