"""Unit tests for the prioritized-replay segment trees. No torch required."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from utils.segment_tree import MinSegmentTree, SumSegmentTree


def test_sum_and_min() -> None:
    tree = SumSegmentTree(8)
    min_tree = MinSegmentTree(8)
    values = [3.0, 1.0, 4.0, 1.0, 5.0, 9.0, 2.0, 6.0]
    for i, value in enumerate(values):
        tree[i] = value
        min_tree[i] = value
    assert abs(tree.sum() - sum(values)) < 1e-9
    assert abs(tree.sum(0, 4) - sum(values[:4])) < 1e-9
    assert min_tree.min() == 1.0
    assert min_tree.min(4, 8) == 2.0


def test_find_prefixsum_index() -> None:
    tree = SumSegmentTree(4)
    for i, value in enumerate([1.0, 2.0, 3.0, 4.0]):
        tree[i] = value
    # cumulative boundaries: [0,1) -> 0, [1,3) -> 1, [3,6) -> 2, [6,10) -> 3
    assert tree.find_prefixsum_index(0.5) == 0
    assert tree.find_prefixsum_index(1.5) == 1
    assert tree.find_prefixsum_index(4.0) == 2
    assert tree.find_prefixsum_index(9.5) == 3


def test_update_reflects_in_sum() -> None:
    tree = SumSegmentTree(4)
    for i in range(4):
        tree[i] = 1.0
    assert tree.sum() == 4.0
    tree[2] = 5.0
    assert tree.sum() == 8.0
    assert tree[2] == 5.0


if __name__ == "__main__":
    test_sum_and_min()
    test_find_prefixsum_index()
    test_update_reflects_in_sum()
    print("segment_tree tests passed")
