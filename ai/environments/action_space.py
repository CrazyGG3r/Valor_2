"""Conversion between agent outputs and the bridge's wire action format.

Wire format (must match _apply_action in scripts/ai/ai_bridge.gd):
    {"move": [x, y], "look": [x, y], "jump": bool, "attack": bool,
     "shoot": bool, "dash": bool, "upgrade": int}

Move axes: x = strafe (+right), y = forward/back (+back, Godot's +Z).
Look x = yaw rate in [-1, 1]. All continuous values are clipped to [-1, 1].

"upgrade" (int 0-2) is only consumed on decision steps -- when the
observation says an upgrade choice is pending, the next step picks that
option index and no simulation time passes.

Continuous agents emit CONTINUOUS_ACTION_SIZE floats:
    [move_x, move_y, look_x, attack, shoot, dash, upgrade]
Button channels press when > 0; the upgrade channel maps [-1, 1] onto
option index 0/1/2 in equal thirds.

Discrete agents index DISCRETE_ACTIONS: every (move, turn) combination
crossed with one-button-at-a-time combat (none/attack/shoot/dash), plus
three dedicated upgrade-choice actions at the end of the table (offset
UPGRADE_ACTION_OFFSET). Non-upgrade actions carry upgrade=0, so on a
decision step any action resolves to a valid choice.
"""
from __future__ import annotations

import numpy as np

# move_x, move_y, look_x, attack, shoot, dash, upgrade
CONTINUOUS_ACTION_SIZE = 7

UPGRADE_CHOICES = 3

_ACTION_DEFAULTS = {
    "jump": False,
    "attack": False,
    "shoot": False,
    "dash": False,
    "upgrade": 0,
}


def continuous_to_action(vector: np.ndarray) -> dict:
    """Map a float vector (CONTINUOUS_ACTION_SIZE) to a wire action dict."""
    v = np.clip(np.asarray(vector, dtype=np.float32), -1.0, 1.0)
    return {
        "move": [float(v[0]), float(v[1])],
        "look": [float(v[2]), 0.0],
        "jump": False,
        "attack": bool(v[3] > 0.0),
        "shoot": bool(v[4] > 0.0),
        "dash": bool(v[5] > 0.0),
        "upgrade": _upgrade_index(float(v[6])),
    }


def _upgrade_index(value: float) -> int:
    """[-1, -1/3) -> 0, [-1/3, 1/3) -> 1, [1/3, 1] -> 2."""
    return int(np.clip(np.floor((value + 1.0) * 1.5), 0, UPGRADE_CHOICES - 1))


def _build_discrete_table() -> list[dict]:
    moves = [(0.0, 0.0)]
    for octant in range(8):  # 8 compass directions
        radians = octant * np.pi / 4.0
        moves.append((float(np.cos(radians)), float(np.sin(radians))))
    turns = [-1.0, 0.0, 1.0]
    buttons = [None, "attack", "shoot", "dash"]
    table: list[dict] = []
    for move_x, move_y in moves:
        for turn in turns:
            for button in buttons:
                action = {"move": [move_x, move_y], "look": [turn, 0.0], **_ACTION_DEFAULTS}
                if button is not None:
                    action[button] = True
                table.append(action)
    # Dedicated upgrade-choice actions; movement no-ops on normal steps.
    for choice in range(UPGRADE_CHOICES):
        table.append({
            "move": [0.0, 0.0], "look": [0.0, 0.0],
            **_ACTION_DEFAULTS, "upgrade": choice,
        })
    return table


# 9 moves x 3 turns x 4 button states + 3 upgrade choices = 111 actions,
# for value-based methods (DQN/Rainbow).
DISCRETE_ACTIONS: list[dict] = _build_discrete_table()
DISCRETE_ACTION_COUNT = len(DISCRETE_ACTIONS)
# DISCRETE_ACTIONS[UPGRADE_ACTION_OFFSET + k] picks upgrade option k.
UPGRADE_ACTION_OFFSET = DISCRETE_ACTION_COUNT - UPGRADE_CHOICES


def discrete_to_action(index: int) -> dict:
    return DISCRETE_ACTIONS[index]
