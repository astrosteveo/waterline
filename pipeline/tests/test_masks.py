import numpy as np
import pytest

from kiln import masks


def wavy(size=64, count=4):
    """A height of `count` soft ridges across a tile, as rows bottom to top."""
    u = np.arange(size) / size
    return np.tile(0.5 + 0.5 * np.cos(2 * np.pi * count * u), (size, 1))


def test_blur_wraps_round_the_edges_and_keeps_the_mean():
    height = np.zeros((32, 32))
    height[0, 0] = 1.0
    blurred = masks.blurred(height, 2.0)
    assert blurred.sum() == pytest.approx(1.0)
    # The corner's blur reaches the other three corners, as a tile's would.
    assert blurred[0, -1] == pytest.approx(blurred[-1, 0])
    assert blurred[0, 0] > blurred[0, -1] > blurred[16, 16]
    assert masks.blurred(height, 0) is not height and (masks.blurred(height, 0) == height).all()


def test_ridges_and_hollows_find_the_crests_and_the_troughs():
    height = wavy()
    ridges, hollows = masks.ridges(height, 3.0), masks.hollows(height, 3.0)
    crest, trough = height[0].argmax(), height[0].argmin()
    assert ridges[0, crest] == pytest.approx(1.0) and ridges[0, trough] == 0.0
    assert hollows[0, trough] == pytest.approx(1.0) and hollows[0, crest] == 0.0
    assert ridges.min() >= 0.0 and hollows.max() <= 1.0
    # A flat height has neither.
    assert not masks.ridges(np.full((8, 8), 0.3), 2.0).any()


def test_occlusion_darkens_the_troughs_more_for_a_deeper_relief():
    height = wavy()
    shallow, deep = masks.occlusion(height, 6.0, depth=2.0), masks.occlusion(height, 6.0, depth=20.0)
    crest, trough = height[0].argmax(), height[0].argmin()
    assert shallow[0, crest] == pytest.approx(1.0) and deep[0, crest] == pytest.approx(1.0)
    assert deep[0, trough] < shallow[0, trough] < 1.0
    assert 0.0 <= deep.min() and deep.max() <= 1.0


def test_masks_of_a_tiling_height_tile():
    rng = np.random.default_rng(1)
    height = masks.blurred(rng.random((64, 64)), 3.0)
    for mask in (masks.ridges(height, 4.0), masks.occlusion(height, 4.0, 10.0)):
        edge = (np.abs(mask[:, 0] - mask[:, -1]).mean() + np.abs(mask[0] - mask[-1]).mean()) / 2
        inside = (np.abs(np.diff(mask, axis=1)).mean() + np.abs(np.diff(mask, axis=0)).mean()) / 2
        assert edge <= inside * 1.5
