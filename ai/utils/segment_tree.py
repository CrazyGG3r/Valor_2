"""Sum and min segment trees for proportional prioritized experience replay.

Both support O(log n) point updates and range queries; SumSegmentTree adds
find_prefixsum_index for sampling proportional to priority.
"""
from __future__ import annotations

import operator
from typing import Callable


class SegmentTree:
    def __init__(self, capacity: int, operation: Callable[[float, float], float],
                 neutral_element: float) -> None:
        assert capacity > 0 and capacity & (capacity - 1) == 0, "capacity must be a power of 2"
        self._capacity = capacity
        self._operation = operation
        self._value = [neutral_element for _ in range(2 * capacity)]

    def _reduce(self, start: int, end: int) -> float:
        result = None
        start += self._capacity
        end += self._capacity
        while start < end:
            if start & 1:
                result = self._value[start] if result is None \
                    else self._operation(result, self._value[start])
                start += 1
            if end & 1:
                end -= 1
                result = self._value[end] if result is None \
                    else self._operation(result, self._value[end])
            start //= 2
            end //= 2
        return result

    def __setitem__(self, index: int, value: float) -> None:
        index += self._capacity
        self._value[index] = value
        index //= 2
        while index >= 1:
            self._value[index] = self._operation(self._value[2 * index], self._value[2 * index + 1])
            index //= 2

    def __getitem__(self, index: int) -> float:
        return self._value[self._capacity + index]


class SumSegmentTree(SegmentTree):
    def __init__(self, capacity: int) -> None:
        super().__init__(capacity, operator.add, 0.0)

    def sum(self, start: int = 0, end: int | None = None) -> float:
        return self._reduce(start, self._capacity if end is None else end)

    def find_prefixsum_index(self, prefixsum: float) -> int:
        """Largest index i such that sum(0..i) <= prefixsum."""
        index = 1
        while index < self._capacity:
            if self._value[2 * index] > prefixsum:
                index = 2 * index
            else:
                prefixsum -= self._value[2 * index]
                index = 2 * index + 1
        return index - self._capacity


class MinSegmentTree(SegmentTree):
    def __init__(self, capacity: int) -> None:
        super().__init__(capacity, min, float("inf"))

    def min(self, start: int = 0, end: int | None = None) -> float:
        return self._reduce(start, self._capacity if end is None else end)
