"""CLI: render every figure for a training run to ai_progress_viz/output/<run>/.

    python ai_progress_viz/plot_run.py <run-name | run-dir | stats.jsonl> [names...]

With no figure names, renders the full ALL_PLOTS registry. Run without args to
list the runs that have research data.
"""
from __future__ import annotations

import sys
from pathlib import Path

# Allow running as a script (python ai_progress_viz/plot_run.py ...) without a
# package install by putting this directory on the path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

import data_loader  # noqa: E402
import plots  # noqa: E402

OUTPUT_DIR = Path(__file__).resolve().parent / "output"


def _print_available_runs() -> None:
    runs = data_loader.list_runs()
    if not runs:
        print(f"No runs with {data_loader.STATS_FILENAME} under "
              f"{data_loader.DEFAULT_LOGS_DIR}")
        return
    print("Available runs:")
    for run_dir in runs:
        print(f"  {run_dir.name}")


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        _print_available_runs()
        return 1

    target = argv[0]
    selected = argv[1:] or list(plots.ALL_PLOTS)

    run = data_loader.load_run(target)
    if not run.episodes:
        print(f"Run '{run.name}' has no episodes recorded yet.")
        return 1

    out_dir = OUTPUT_DIR / run.name
    out_dir.mkdir(parents=True, exist_ok=True)

    for name in selected:
        builder = plots.ALL_PLOTS.get(name)
        if builder is None:
            print(f"  ! unknown figure '{name}' (known: {', '.join(plots.ALL_PLOTS)})")
            continue
        figure = builder(run)
        destination = out_dir / f"{name}.png"
        figure.savefig(destination, dpi=120)
        print(f"  wrote {destination}")

    print(f"Done: {run.name} ({len(run.episodes)} episodes) -> {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
