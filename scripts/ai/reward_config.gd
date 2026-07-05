class_name RewardConfig
extends Resource
## Tunable reward shaping for RL training. Edit res://configs/reward_config.tres
## in the inspector instead of touching code. Values are per event unless noted.

@export var survive_per_second := 0.1
@export var kill := 1.0
## Per point of damage received (negative).
@export var damage_taken := -0.05
@export var death := -10.0
## Granted each time a new wave spawns after the first (you survived one).
@export var wave_survived := 2.0

@export_group("Reserved for future systems")
@export var xp_collected := 0.5
@export var level_up := 5.0
## Per point of damage dealt.
@export var damage_dealt := 0.02

@export_group("Action shaping")
## Per melee swing. Set negative to tax mindless spam so the agent only swings
## when it actually connects -- the main lever against berserk melee.
@export var melee_swing := 0.0
## Per shot fired. Usually leave at 0: paying per shot just teaches the agent to
## spam bullets the same way it spams melee. Nudge slightly positive only to
## bootstrap early exploration, then return to 0.
@export var shot_fired := 0.0
## Per dash. A small positive value bootstraps dodging (which otherwise earns no
## reward and is never explored). Drop back toward 0 once dashing appears.
@export var dash_used := 0.0
