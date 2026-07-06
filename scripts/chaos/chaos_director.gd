class_name ChaosDirector
extends Node3D
## Chaos Mode's scheduler. Picks random events off the registered list and
## spawns them in SALVOS -- bursts of N staggered instances (meteor showers,
## lightning storms) -- driven by an intensity curve that climbs over the
## run: intervals shrink, salvos grow, cooldowns compress. A fail-safe fires
## the next salvo immediately whenever the arena has no hazard active or
## queued, so the arena never goes quiet.
##
## The director knows NOTHING about individual event implementations -- only
## the ChaosEvent contract (cooldown, salvo_max, salvo_stagger, begin()) --
## so adding a new event is: write a ChaosEvent subclass, wrap it in a
## one-node scene, append it to event_scenes in the inspector.
##
## Ties itself to the GameManager (group lookup) so runs starting/ending
## restart/stop the chaos stream. In the "chaos_director" group so the AI
## observation layer can later find it and read get_active_hazards().

signal event_started(event: ChaosEvent)
signal event_finished(event: ChaosEvent)

## Decorrelates this RNG stream from the spawner (seed), upgrades (seed + 1),
## and obstacles (seed + 2) when seeded runs land for chaos training.
const SEED_OFFSET := 3

## The event roster. Each scene's root must extend ChaosEvent.
@export var event_scenes: Array[PackedScene] = []
@export var initial_delay := 2.0

@export_group("Intensity Curve")
## Seconds between salvos at intensity 0 / at full intensity.
@export var start_interval := 5.5
@export var min_interval := 1.6
## Run seconds to reach full intensity.
@export var ramp_duration := 240.0
## Curve shape: < 1 ramps hard early then eases in (chaos arrives fast).
@export_range(0.1, 3.0) var intensity_exponent := 0.7
## Event cooldown multiplier at full intensity (1.0 = no compression).
@export_range(0.1, 1.0) var cooldown_scale_at_peak := 0.55

@export_group("Limits")
## Hard cap on live + queued event INSTANCES (salvo members count singly).
@export var max_active_events := 30
## Events position themselves within this half-extent around the director.
@export var arena_half_extent := 24.0
## 0 = random every run; anything else makes the event stream reproducible.
@export var random_seed := 0
## Start scheduling immediately (for test scenes without a GameManager).
@export var auto_start := false

var _rng := RandomNumberGenerator.new()
var _cooldowns: Array[float] = []
var _active_events: Array[ChaosEvent] = []
## Committed salvo members awaiting their stagger delay: {index:int, delay:float}
var _pending: Array[Dictionary] = []
var _next_salvo_in := 0.0
var _elapsed := 0.0
var _running := false


func _ready() -> void:
	add_to_group(&"chaos_director")
	_cooldowns.resize(event_scenes.size())
	_cooldowns.fill(0.0)
	# The GameManager registers its group in _enter_tree, so it is findable
	# here even though our _ready runs before its own.
	var game := get_tree().get_first_node_in_group(&"game_manager") as GameManager
	if game != null:
		game.run_started.connect(_on_run_started)
		game.run_ended.connect(_on_run_ended)
	elif auto_start:
		restart(random_seed)


func _physics_process(delta: float) -> void:
	# Raw (time-scaled) delta throughout: hazard pacing must track the same
	# clock as player physics and hitbox cooldowns at any training speed.
	if not _running:
		return
	_elapsed += delta
	for i in _cooldowns.size():
		_cooldowns[i] = maxf(_cooldowns[i] - delta, 0.0)
	_drain_pending(delta)
	# Never-bland fail-safe: an empty arena skips the remaining interval.
	if _active_events.is_empty() and _pending.is_empty():
		_next_salvo_in = minf(_next_salvo_in, 0.1)
	_next_salvo_in -= delta
	if _next_salvo_in <= 0.0 \
			and _active_events.size() + _pending.size() < max_active_events:
		_try_start_salvo()


## 0..1 chaos level for the current run time; drives interval, salvo size,
## and cooldown compression. Public so the AI observation layer can read it.
func intensity() -> float:
	var progress := clampf(_elapsed / maxf(ramp_duration, 0.001), 0.0, 1.0)
	return pow(progress, intensity_exponent)


## Clears any live hazards and starts a fresh event stream.
func restart(seed_value: int = 0) -> void:
	for event in _active_events.duplicate():
		event.cancel()
	_active_events.clear()
	_pending.clear()
	_cooldowns.fill(0.0)
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value + SEED_OFFSET
	_elapsed = 0.0
	_next_salvo_in = initial_delay
	_running = true


func stop() -> void:
	_running = false
	_pending.clear()
	for event in _active_events.duplicate():
		event.cancel()
	_active_events.clear()


## Snapshot of every live hazard (each event self-describes). This is the
## hook the RL observation builder will consume; no reward logic lives here.
func get_active_hazards() -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	for event in _active_events:
		hazards.append(event.hazard_info())
	return hazards


# --- scheduling ---------------------------------------------------------------


func _try_start_salvo() -> void:
	var candidates: Array[int] = []
	for i in event_scenes.size():
		if event_scenes[i] != null and _cooldowns[i] <= 0.0:
			candidates.append(i)
	var index := -1
	if not candidates.is_empty():
		index = candidates[_rng.randi_range(0, candidates.size() - 1)]
	elif _active_events.is_empty() and _pending.is_empty():
		# Everything is cooling but the arena is empty: force whichever event
		# is closest to ready rather than leave the player unpressured.
		index = _soonest_ready_index()
	if index < 0:
		_next_salvo_in = 0.25  # all cooling, hazards still live; retry shortly
		return
	# Spawn the first instance immediately; its exports tell us how big this
	# salvo gets and how the roster cooldown should be set.
	var first := _spawn_instance(index)
	if first == null:
		return
	var count := _salvo_count(first.salvo_max)
	for n in range(1, count):
		_pending.append({"index": index, "delay": first.salvo_stagger * float(n)})
	_cooldowns[index] = first.cooldown * lerpf(1.0, cooldown_scale_at_peak, intensity())
	_next_salvo_in = _roll_interval()


func _drain_pending(delta: float) -> void:
	var due: Array[int] = []
	for i in _pending.size():
		_pending[i]["delay"] -= delta
		if float(_pending[i]["delay"]) <= 0.0:
			due.push_front(i)  # reverse order so removals don't shift pending indices
	for i in due:
		var index := int(_pending[i]["index"])
		_pending.remove_at(i)
		_spawn_instance(index)


func _spawn_instance(index: int) -> ChaosEvent:
	var event := event_scenes[index].instantiate() as ChaosEvent
	if event == null:
		push_warning("ChaosDirector: scene %d's root is not a ChaosEvent." % index)
		_cooldowns[index] = INF  # never pick a broken entry again
		return null
	event.rng = _rng
	event.arena_center = global_position
	event.arena_half_extent = arena_half_extent
	add_child(event)
	_active_events.append(event)
	event.finished.connect(_on_event_finished)
	event.begin()
	event_started.emit(event)
	return event


func _salvo_count(salvo_max: int) -> int:
	if salvo_max <= 1:
		return 1
	var count := 1 + roundi(float(salvo_max - 1) * intensity() * _rng.randf_range(0.7, 1.0))
	return clampi(count, 1, salvo_max)


func _roll_interval() -> float:
	return lerpf(start_interval, min_interval, intensity()) * _rng.randf_range(0.8, 1.25)


func _soonest_ready_index() -> int:
	var best := -1
	var best_left := INF
	for i in event_scenes.size():
		if event_scenes[i] != null and _cooldowns[i] < best_left:
			best_left = _cooldowns[i]
			best = i
	if best >= 0:
		_cooldowns[best] = 0.0
	return best


func _on_event_finished(event: ChaosEvent) -> void:
	_active_events.erase(event)
	event_finished.emit(event)


func _on_run_started() -> void:
	restart(random_seed)


func _on_run_ended(_stats: Dictionary) -> void:
	stop()
