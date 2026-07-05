# episode_stats.jsonl schema

One JSON object per line, one line per episode, appended in episode order.
Written by `ai/utils/run_logger.py`; the game-side fields come from
`GameManager.episode_stats()` (Godot). Treat this as the contract between the
training stack and `ai_progress_viz` — add fields, don't repurpose existing
ones.

| Field            | Type              | Source        | Meaning |
|------------------|-------------------|---------------|---------|
| `episode`        | int               | trainer       | 1-based episode index within the run |
| `reward`         | float             | trainer       | Total shaped reward for the episode |
| `steps`          | int               | trainer       | Agent decision steps taken |
| `wave`           | int               | game          | Highest wave reached |
| `time`           | float (s)         | game          | Survival time in simulated seconds |
| `kills`          | int               | game          | Enemies killed |
| `shots_fired`    | int               | game          | Projectiles fired by the player |
| `dashes`         | int               | game          | Dashes performed |
| `melee_swings`   | int               | game          | Melee swings performed |
| `damage_dealt`   | float             | game          | Total damage dealt to enemies |
| `damage_taken`   | float             | game          | Total damage taken by the player |
| `kills_by_type`  | dict[str, int]    | game          | Kills split by enemy type: `melee`/`tank`/`ranged`/`unknown` |
| `damage_taken_by_type` | dict[str, float] | game     | Damage taken split by the enemy type that dealt it |
| `final_health`   | float             | game          | Player health at episode end |
| `max_health`     | float             | game          | Player max health at episode end (after upgrades) |
| `move_speed`     | float             | game          | Final move-speed stat (after upgrades) |
| `peak_speed`     | float             | game          | Peak horizontal velocity observed |
| `level`          | int               | game          | Final player level |
| `upgrade_order`  | list[str]         | game          | Upgrade display names in the order chosen |
| `upgrade_counts` | dict[str, int]    | game          | Upgrade id -> times taken this run |

Notes:
- `upgrade_order` preserves selection order (research signal for skill-choice
  strategy); `upgrade_counts` is the multiset by upgrade id.
- `kills_by_type` / `damage_taken_by_type` always carry all four keys (seeded to
  zero), so per-type columns are dense; their values sum to `kills` /
  `damage_taken` respectively (`unknown` catches unattributed sources).
- New fields may appear over time; loaders should tolerate missing keys.
