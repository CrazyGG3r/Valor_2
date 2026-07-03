"""Unit tests for observation flattening. No Godot or PyTorch required.

Run directly (python tests/test_observation.py) or via pytest.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np

from environments.valor_env import (
    ENEMY_FEATURES,
    ENEMY_SLOTS_OFFSET,
    MAX_TRACKED_ENEMIES,
    OBS_SIZE,
    ValorEnv,
)


def _fake_observation(enemy_count: int) -> dict:
    return {
        "player": {
            "position": [2.0, 1.0, -4.0],
            "velocity_local": [1.0, 0.0, -2.5],
            "yaw": np.pi / 2.0,
            "health": 80.0,
            "max_health": 100.0,
            "cooldowns": {"melee": 0.25, "shoot": 0.5, "dash": 1.0},
        },
        "enemies": [
            {"position": [float(i + 1), 0.0, 0.0], "distance": float(i + 1)}
            for i in range(enemy_count)
        ],
        "enemy_count": enemy_count,
        "wave": 3,
        "time": 30.0,
    }


def test_flatten_shape_and_values() -> None:
    env = ValorEnv()  # never connects; _flatten is pure
    vector = env._flatten(_fake_observation(enemy_count=2))
    assert vector.shape == (OBS_SIZE,)
    assert vector.dtype == np.float32
    assert vector[0] == np.float32(0.8)  # health fraction
    assert abs(vector[5] - 1.0) < 1e-6  # sin(pi/2)
    assert vector[10] == np.float32(0.25)  # melee cooldown
    assert vector[11] == np.float32(0.5)  # shoot cooldown
    assert vector[12] == np.float32(1.0)  # dash cooldown
    assert vector[ENEMY_SLOTS_OFFSET] == 1.0  # first enemy slot present
    assert vector[ENEMY_SLOTS_OFFSET + ENEMY_FEATURES] == 1.0  # second slot present
    assert vector[ENEMY_SLOTS_OFFSET + 2 * ENEMY_FEATURES] == 0.0  # third slot empty


def test_flatten_caps_enemies() -> None:
    env = ValorEnv()
    vector = env._flatten(_fake_observation(enemy_count=MAX_TRACKED_ENEMIES + 3))
    assert vector.shape == (OBS_SIZE,)
    last_slot = ENEMY_SLOTS_OFFSET + (MAX_TRACKED_ENEMIES - 1) * ENEMY_FEATURES
    assert vector[last_slot] == 1.0


if __name__ == "__main__":
    test_flatten_shape_and_values()
    test_flatten_caps_enemies()
    print("observation tests passed")
