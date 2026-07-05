"""Device selection shared by every learning algorithm.

"auto" (the default everywhere) resolves to CUDA when a GPU build of PyTorch
is installed, otherwise CPU. Set "device": "cpu"/"cuda"/"cuda:1" in an
algorithm's config JSON to override.
"""
from __future__ import annotations

import torch

_announced: set[str] = set()


def resolve_device(name: str = "auto") -> torch.device:
    if name == "auto":
        name = "cuda" if torch.cuda.is_available() else "cpu"
    device = torch.device(name)
    if device.type == "cuda" and not torch.cuda.is_available():
        print("WARNING: CUDA requested but not available; falling back to CPU. "
              "Install a GPU build: pip install torch --index-url "
              "https://download.pytorch.org/whl/cu128")
        device = torch.device("cpu")
    label = str(device)
    if label not in _announced:  # announce once per process, not per agent
        _announced.add(label)
        if device.type == "cuda":
            index = device.index if device.index is not None else 0
            print(f"Using GPU: {torch.cuda.get_device_name(index)}")
        else:
            print("Using CPU (no CUDA device available)")
    return device
