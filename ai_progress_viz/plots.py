"""Matplotlib figure builders over a loaded `Run` (see data_loader.py).

Each `plot_*` function takes a Run and returns a matplotlib Figure, so callers
decide whether to show, save, or embed it. matplotlib is an optional dependency;
importing this module without it raises a clear error only when a plot is built.
"""
from __future__ import annotations

from collections import Counter
from typing import TYPE_CHECKING

from data_loader import Run

if TYPE_CHECKING:  # avoid a hard import at module load
    from matplotlib.figure import Figure


def _mpl():
    try:
        import matplotlib.pyplot as plt
    except ImportError as error:  # pragma: no cover
        raise ImportError(
            "ai_progress_viz plots require matplotlib: pip install matplotlib"
        ) from error
    return plt


def _smooth(values: list[float], window: int = 20) -> list[float]:
    """Trailing moving average; window shrinks near the start."""
    if window <= 1 or len(values) < 2:
        return values
    smoothed: list[float] = []
    running = 0.0
    for i, value in enumerate(values):
        running += value
        if i >= window:
            running -= values[i - window]
        smoothed.append(running / min(i + 1, window))
    return smoothed


def plot_reward_curve(run: Run) -> "Figure":
    plt = _mpl()
    reward = run.series("reward")
    episodes = run.series("episode")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(episodes, reward, alpha=0.3, label="reward")
    ax.plot(episodes, _smooth(reward), color="C0", label="reward (smoothed)")
    ax.set_title(f"Reward — {run.name}")
    ax.set_xlabel("episode")
    ax.set_ylabel("total reward")
    ax.legend(loc="best")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    return fig


def plot_action_mix(run: Run) -> "Figure":
    """Per-episode combat action counts — reveals melee/shoot/dash balance."""
    plt = _mpl()
    episodes = run.series("episode")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    for field, color in (("melee_swings", "C3"), ("shots_fired", "C0"), ("dashes", "C2")):
        ax.plot(episodes, _smooth(run.series(field)), color=color, label=field)
    ax.set_title(f"Action mix (smoothed) — {run.name}")
    ax.set_xlabel("episode")
    ax.set_ylabel("count per episode")
    ax.legend(loc="best")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    return fig


def plot_damage(run: Run) -> "Figure":
    plt = _mpl()
    episodes = run.series("episode")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    ax.plot(episodes, _smooth(run.series("damage_dealt")), color="C0", label="dealt")
    ax.plot(episodes, _smooth(run.series("damage_taken")), color="C3", label="taken")
    ax.set_title(f"Damage dealt vs taken (smoothed) — {run.name}")
    ax.set_xlabel("episode")
    ax.set_ylabel("damage")
    ax.legend(loc="best")
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    return fig


def plot_survival(run: Run) -> "Figure":
    """Wave reached and survival time on twin axes."""
    plt = _mpl()
    episodes = run.series("episode")
    fig, ax_wave = plt.subplots(figsize=(9, 4.5))
    ax_wave.plot(episodes, _smooth(run.series("wave")), color="C4", label="wave")
    ax_wave.set_xlabel("episode")
    ax_wave.set_ylabel("wave reached", color="C4")
    ax_time = ax_wave.twinx()
    ax_time.plot(episodes, _smooth(run.series("time")), color="C1", label="time (s)")
    ax_time.set_ylabel("survival time (s)", color="C1")
    ax_wave.set_title(f"Survival (smoothed) — {run.name}")
    ax_wave.grid(True, alpha=0.3)
    fig.tight_layout()
    return fig


def plot_upgrade_order(run: Run) -> "Figure":
    """Heatmap of which upgrade is chosen at each pick position across the run.

    Answers 'what does the agent grab first?' — column = pick index (1st, 2nd,
    ...), row = upgrade, cell = how often that upgrade landed in that slot.
    """
    plt = _mpl()
    orders = [o for o in run.column("upgrade_order") if o]
    labels: list[str] = []
    seen: set[str] = set()
    max_picks = 0
    for order in orders:
        max_picks = max(max_picks, len(order))
        for name in order:
            if name not in seen:
                seen.add(name)
                labels.append(name)

    fig, ax = plt.subplots(figsize=(9, max(3.0, 0.5 * len(labels) + 1.5)))
    if not labels or max_picks == 0:
        ax.text(0.5, 0.5, "no upgrades recorded", ha="center", va="center")
        ax.set_axis_off()
        fig.tight_layout()
        return fig

    row_of = {name: i for i, name in enumerate(labels)}
    grid = [[0 for _ in range(max_picks)] for _ in labels]
    for order in orders:
        for pick_index, name in enumerate(order):
            grid[row_of[name]][pick_index] += 1

    image = ax.imshow(grid, aspect="auto", cmap="magma")
    ax.set_xticks(range(max_picks))
    ax.set_xticklabels([f"#{i + 1}" for i in range(max_picks)])
    ax.set_yticks(range(len(labels)))
    ax.set_yticklabels(labels)
    ax.set_title(f"Upgrade pick order — {run.name}")
    ax.set_xlabel("pick position")
    fig.colorbar(image, ax=ax, label="times chosen")
    fig.tight_layout()
    return fig


ENEMY_TYPES = ("melee", "tank", "ranged", "unknown")
_TYPE_COLORS = {"melee": "C3", "tank": "C5", "ranged": "C0", "unknown": "C7"}


def _per_type_series(run: Run, field: str, key: str) -> list[float]:
    """Column of one enemy-type's value from a dict-valued field per episode."""
    return [float((row or {}).get(key, 0) or 0) for row in run.column(field)]


def _plot_per_type(run: Run, field: str, title: str, ylabel: str) -> "Figure":
    plt = _mpl()
    episodes = run.series("episode")
    fig, ax = plt.subplots(figsize=(9, 4.5))
    drawn = False
    for enemy_type in ENEMY_TYPES:
        values = _per_type_series(run, field, enemy_type)
        if not any(values):
            continue  # skip types that never contributed (keeps legend clean)
        ax.plot(episodes, _smooth(values), color=_TYPE_COLORS[enemy_type], label=enemy_type)
        drawn = True
    if not drawn:
        ax.text(0.5, 0.5, f"no '{field}' data", ha="center", va="center")
        ax.set_axis_off()
    else:
        ax.set_xlabel("episode")
        ax.set_ylabel(ylabel)
        ax.legend(loc="best")
        ax.grid(True, alpha=0.3)
    ax.set_title(f"{title} (smoothed) — {run.name}")
    fig.tight_layout()
    return fig


def plot_kills_by_type(run: Run) -> "Figure":
    return _plot_per_type(run, "kills_by_type", "Kills by enemy type", "kills / episode")


def plot_damage_by_type(run: Run) -> "Figure":
    return _plot_per_type(
        run, "damage_taken_by_type", "Damage taken by enemy type", "damage / episode")


# Registry the CLI iterates; extend as new views are added.
ALL_PLOTS = {
    "reward": plot_reward_curve,
    "action_mix": plot_action_mix,
    "damage": plot_damage,
    "damage_by_type": plot_damage_by_type,
    "survival": plot_survival,
    "kills_by_type": plot_kills_by_type,
    "upgrade_order": plot_upgrade_order,
}
