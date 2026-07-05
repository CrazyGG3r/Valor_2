# ai_progress_viz — AI progress visualization

The third component of Valor 2, alongside the Godot game (simulator) and `ai/`
(the RL training stack). This package **reads** the per-episode research data
that training writes and turns it into plots. It never touches Godot or the
training loop — strictly a consumer, so it can evolve independently.

```
Godot game  --emits stats-->  ai/ (RunLogger)  --writes-->  episode_stats.jsonl
                                                                   |
                                                    ai_progress_viz reads & plots
```

## Data source

Each training/eval run writes one line of JSON per episode to
`ai/logs/<run_name>/episode_stats.jsonl`. The schema is documented in
[SCHEMA.md](SCHEMA.md) and produced by `GameManager.episode_stats()` in Godot,
merged with `episode`/`reward`/`steps` by `ai/utils/run_logger.py`.

## Layout

```
ai_progress_viz/
├── README.md          # this file
├── SCHEMA.md          # the per-episode record schema (the contract)
├── data_loader.py     # discover runs, load episode_stats.jsonl (stdlib only)
├── plots.py           # matplotlib figure builders (one per view)
├── plot_run.py        # CLI: render a run's figures to output/
└── output/            # generated PNGs (created on demand)
```

## Usage

```bash
# Install plotting deps (kept optional so the loader works without them):
pip install matplotlib

# Render every figure for a run into ai_progress_viz/output/<run>/
python ai_progress_viz/plot_run.py rainbow-train-20260705-001259

# Or point at any run directory / stats file directly:
python ai_progress_viz/plot_run.py path/to/episode_stats.jsonl
```

`data_loader.py` has no third-party dependencies, so notebooks and custom
analysis can `from ai_progress_viz import data_loader` and work with plain
dicts (or a pandas DataFrame via `load_run_dataframe`, if pandas is installed).

## Foundation status

This is scaffolding: the loader is complete, and `plots.py` ships a starter set
(reward curve, action mix, damage, survival, upgrade-order heatmap). Add new
figure builders to `plots.py` and register them in `plot_run.py` as the
research questions grow.
