"""Conversion between agent outputs and the bridge's wire action format.

Wire format (must match _apply_action in scripts/ai/ai_bridge.gd):
    {"move": [x, y], "look": [x, y], "jump": bool, "attack": bool,
     "shoot": bool, "dash": bool}

Move axes: x = strafe (+right), y = forward/back (+back, Godot's +Z).
Look x = yaw rate in [-1, 1]. All continuous values are clipped to [-1, 1].

"upgrade" (int 0-2) is only consumed on decision steps -- when the
observation says an upgrade choice is pending, the next step picks that
option index and no simulation time passes. Default 0 = first option.
"""
from __future__ import annotations

import numpy as np

CONTINUOUS_ACTION_SIZE = 3  # move_x, move_y, look_x

_ACTION_DEFAULTS = {
    "jump": False,
    "attack": False,
    "shoot": False,
    "dash": False,
    "upgrade": 0,
}


def continuous_to_action(vector: np.ndarray) -> dict:
    """Map a float vector [move_x, move_y, look_x] to a wire action dict."""
    v = np.clip(np.asarray(vector, dtype=np.float32), -1.0, 1.0)
    return {
        "move": [float(v[0]), float(v[1])],
        "look": [float(v[2]), 0.0],
        **_ACTION_DEFAULTS,
    }


def _build_discrete_table() -> list[dict]:
    moves = [(0.0, 0.0)]
    for octant in range(8):  # 8 compass directions
        radians = octant * np.pi / 4.0
        moves.append((float(np.cos(radians)), float(np.sin(radians))))
    turns = [-1.0, 0.0, 1.0]
    return [
        {"move": [move_x, move_y], "look": [turn, 0.0], **_ACTION_DEFAULTS}
        for move_x, move_y in moves
        for turn in turns
    ]


# 9 move options x 3 turn options = 27 actions, for value-based methods (DQN).
DISCRETE_ACTIONS: list[dict] = _build_discrete_table()
DISCRETE_ACTION_COUNT = len(DISCRETE_ACTIONS)


def discrete_to_action(index: int) -> dict:
    return DISCRETE_ACTIONS[index]
