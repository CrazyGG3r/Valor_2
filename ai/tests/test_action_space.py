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
    UPGRADE_ACTION_OFFSET,
    UPGRADE_CHOICES,
    continuous_to_action,
    discrete_to_action,
)

WIRE_KEYS = {"move", "look", "jump", "attack", "shoot", "dash", "upgrade"}


def test_discrete_table() -> None:
    # 9 moves x 3 turns x 4 button states + 3 upgrade choices
    assert DISCRETE_ACTION_COUNT == 9 * 3 * 4 + UPGRADE_CHOICES == 111
    for action in DISCRETE_ACTIONS:
        assert set(action) == WIRE_KEYS
        assert all(-1.0 <= value <= 1.0 for value in action["move"] + action["look"])
        # One combat button at a time keeps the table small.
        assert sum([action["attack"], action["shoot"], action["dash"]]) <= 1
    assert discrete_to_action(0) is DISCRETE_ACTIONS[0]


def test_discrete_combat_buttons_present() -> None:
    assert any(action["attack"] for action in DISCRETE_ACTIONS)
    assert any(action["shoot"] for action in DISCRETE_ACTIONS)
    assert any(action["dash"] for action in DISCRETE_ACTIONS)


def test_discrete_upgrade_actions() -> None:
    for choice in range(UPGRADE_CHOICES):
        action = discrete_to_action(UPGRADE_ACTION_OFFSET + choice)
        assert action["upgrade"] == choice
        assert action["move"] == [0.0, 0.0]  # no-op on non-decision steps
        assert not (action["attack"] or action["shoot"] or action["dash"])
    # Every non-upgrade action still resolves to a valid default choice.
    for action in DISCRETE_ACTIONS[:UPGRADE_ACTION_OFFSET]:
        assert action["upgrade"] == 0


def test_continuous_clipping_and_buttons() -> None:
    action = continuous_to_action(np.array([5.0, -5.0, 0.5, 1.0, -1.0, 0.2, 0.0]))
    assert action["move"] == [1.0, -1.0]
    assert action["look"][0] == np.float32(0.5)
    assert action["jump"] is False
    assert action["attack"] is True
    assert action["shoot"] is False
    assert action["dash"] is True


def test_continuous_upgrade_mapping() -> None:
    def upgrade_of(value: float) -> int:
        vector = np.zeros(CONTINUOUS_ACTION_SIZE)
        vector[6] = value
        return continuous_to_action(vector)["upgrade"]

    assert upgrade_of(-1.0) == 0
    assert upgrade_of(-0.5) == 0
    assert upgrade_of(0.0) == 1
    assert upgrade_of(0.5) == 2
    assert upgrade_of(1.0) == 2


def test_continuous_size_constant() -> None:
    assert CONTINUOUS_ACTION_SIZE == 7


if __name__ == "__main__":
    test_discrete_table()
    test_discrete_combat_buttons_present()
    test_discrete_upgrade_actions()
    test_continuous_clipping_and_buttons()
    test_continuous_upgrade_mapping()
    test_continuous_size_constant()
    print("action_space tests passed")
