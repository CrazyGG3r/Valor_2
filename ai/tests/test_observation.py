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
    MAX_TRACKED_PROJECTILES,
    OBS_SIZE,
    PROJECTILE_FEATURES,
    PROJECTILE_SLOTS_OFFSET,
    ValorEnv,
)


def _fake_observation(enemy_count: int, projectile_count: int = 0) -> dict:
    return {
        "player": {
            "position": [2.0, 1.0, -4.0],
            "velocity_local": [1.0, 0.0, -2.5],
            "yaw": np.pi / 2.0,
            "health": 80.0,
            "max_health": 100.0,
            "cooldowns": {"melee": 0.25, "shoot": 0.5, "dash": 1.0},
            "level": 4,
            "xp_fraction": 0.5,
        },
        "enemies": [
            {
                "position": [float(i + 1), 0.0, 0.0],
                "distance": float(i + 1),
                "type": i % 3,
                "health_fraction": 0.5,
            }
            for i in range(enemy_count)
        ],
        "enemy_count": enemy_count,
        "projectiles": [
            {
                "position": [float(i + 1), 0.0, -2.0],
                "velocity": [-10.0, 0.0, 5.0],
                "distance": float(i + 2),
            }
            for i in range(projectile_count)
        ],
        "wave": 3,
        "time": 30.0,
        "upgrade": {"pending": True, "options": [2, 0, 5]},
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
    assert abs(vector[13] - 0.4) < 1e-6  # level 4 / 10
    assert vector[14] == np.float32(0.5)  # xp fraction
    assert vector[15] == 1.0  # upgrade pending
    assert abs(vector[16] - 3.0 / 6.0) < 1e-6  # option pool index 2
    assert abs(vector[17] - 1.0 / 6.0) < 1e-6  # option pool index 0
    assert abs(vector[18] - 1.0) < 1e-6  # option pool index 5
    assert vector[ENEMY_SLOTS_OFFSET] == 1.0  # first enemy slot present
    assert vector[ENEMY_SLOTS_OFFSET + ENEMY_FEATURES] == 1.0  # second slot present
    assert vector[ENEMY_SLOTS_OFFSET + 2 * ENEMY_FEATURES] == 0.0  # third slot empty


def test_flatten_enemy_type_and_health() -> None:
    env = ValorEnv()
    vector = env._flatten(_fake_observation(enemy_count=3))
    for slot in range(3):
        base = ENEMY_SLOTS_OFFSET + slot * ENEMY_FEATURES
        assert vector[base + 4] == np.float32(0.5)  # health fraction
        one_hot = vector[base + 5:base + 8]
        assert one_hot.sum() == 1.0
        assert one_hot[slot % 3] == 1.0  # type from _fake_observation


def test_flatten_projectiles() -> None:
    env = ValorEnv()
    vector = env._flatten(_fake_observation(enemy_count=0, projectile_count=2))
    base = PROJECTILE_SLOTS_OFFSET
    assert vector[base] == 1.0  # first projectile present
    assert abs(vector[base + 1] - 1.0 / env.projectile_radius) < 1e-6
    assert abs(vector[base + 2] - (-2.0 / env.projectile_radius)) < 1e-6
    assert abs(vector[base + 3] - (-10.0 / env.projectile_speed)) < 1e-6
    assert abs(vector[base + 4] - (5.0 / env.projectile_speed)) < 1e-6
    assert abs(vector[base + 5] - 2.0 / env.projectile_radius) < 1e-6
    assert vector[base + PROJECTILE_FEATURES] == 1.0  # second slot present
    assert vector[base + 2 * PROJECTILE_FEATURES] == 0.0  # third slot empty


def test_flatten_missing_projectiles_key() -> None:
    # Older observations without a projectiles list still flatten cleanly.
    env = ValorEnv()
    obs = _fake_observation(enemy_count=1)
    del obs["projectiles"]
    vector = env._flatten(obs)
    assert vector.shape == (OBS_SIZE,)
    assert vector[PROJECTILE_SLOTS_OFFSET] == 0.0


def test_flatten_caps_enemies_and_projectiles() -> None:
    env = ValorEnv()
    vector = env._flatten(_fake_observation(
        enemy_count=MAX_TRACKED_ENEMIES + 3,
        projectile_count=MAX_TRACKED_PROJECTILES + 2))
    assert vector.shape == (OBS_SIZE,)
    last_enemy = ENEMY_SLOTS_OFFSET + (MAX_TRACKED_ENEMIES - 1) * ENEMY_FEATURES
    assert vector[last_enemy] == 1.0
    last_projectile = (
        PROJECTILE_SLOTS_OFFSET + (MAX_TRACKED_PROJECTILES - 1) * PROJECTILE_FEATURES)
    assert vector[last_projectile] == 1.0


if __name__ == "__main__":
    test_flatten_shape_and_values()
    test_flatten_enemy_type_and_health()
    test_flatten_projectiles()
    test_flatten_missing_projectiles_key()
    test_flatten_caps_enemies_and_projectiles()
    print("observation tests passed")
