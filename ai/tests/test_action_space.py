"""Unit tests for action conversion. No Godot or PyTorch required.

Run directly (python tests/test_action_space.py) or via pytest.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np

from environments.action_space import (
    CONTINUOUS_ACTION_SIZE,
    DISCRETE_ACTION_COUNT,
    DISCRETE_ACTIONS,
    continuous_to_action,
    discrete_to_action,
)


def test_discrete_table() -> None:
    assert DISCRETE_ACTION_COUNT == 27  # 9 move options x 3 turns
    for action in DISCRETE_ACTIONS:
        assert set(action) == {"move", "look", "jump", "attack", "shoot", "dash"}
        assert all(-1.0 <= value <= 1.0 for value in action["move"] + action["look"])
    assert discrete_to_action(0) is DISCRETE_ACTIONS[0]


def test_continuous_clipping() -> None:
    action = continuous_to_action(np.array([5.0, -5.0, 0.5]))
    assert action["move"] == [1.0, -1.0]
    assert action["look"][0] == np.float32(0.5)
    assert action["jump"] is False


def test_continuous_size_constant() -> None:
    assert CONTINUOUS_ACTION_SIZE == 3


if __name__ == "__main__":
    test_discrete_table()
    test_continuous_clipping()
    test_continuous_size_constant()
    print("action_space tests passed")
