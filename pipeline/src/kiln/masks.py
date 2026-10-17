"""Masks worked out from a baked height, for texture recipes: what a node graph evaluated one
pixel at a time can't see, as each looks at the pixels round it. Every mask wraps round the
edges, so a tiling height gives tiling masks.

Arrays are a tile's pixels (rows bottom to top, as Blender bakes them), and sizes are in
pixels; `kiln.blender.shading.TextureKit` turns metres into pixels. Plain numpy, so it runs
and is tested without Blender.
"""
from __future__ import annotations

import numpy as np

# The share of a mask's pixels below its top value, when a mask is scaled so its top is 1:
# a few outliers don't squash the rest.
TOP = 99.0


def blurred(pixels: np.ndarray, radius: float) -> np.ndarray:
    """`pixels` blurred over about `radius` pixels (a Gaussian, `radius` its standard
    deviation), wrapping round the edges."""
    if radius <= 0:
        return pixels.copy()
    fy = np.fft.fftfreq(pixels.shape[0])[:, None]
    fx = np.fft.fftfreq(pixels.shape[1])[None, :]
    kernel = np.exp(-2.0 * (np.pi * radius) ** 2 * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(pixels) * kernel))


def ridges(height: np.ndarray, radius: float) -> np.ndarray:
    """How far each pixel stands above the height round it (within about `radius` pixels),
    0 to 1: edges and crests, where a surface wears. Scaled so all but the top 1% are below 1."""
    above = np.maximum(height - blurred(height, radius), 0.0)
    return _scaled(above)


def hollows(height: np.ndarray, radius: float) -> np.ndarray:
    """How far each pixel lies below the height round it (within about `radius` pixels),
    0 to 1: cracks, pits and the gaps between things, where dirt and water gather."""
    below = np.maximum(blurred(height, radius) - height, 0.0)
    return _scaled(below)


def occlusion(height: np.ndarray, radius: float, depth: float) -> np.ndarray:
    """Ambient occlusion from a height: 1 where nothing round a pixel rises above it, toward 0
    deep in a hollow. `depth` is how many pixels' worth of distance a height of 1 stands, so
    the slopes come out right (a texture's relief over the size of a pixel). Looks at the
    surroundings at a quarter, a half and all of `radius` pixels: how steeply the height
    round a pixel rises above it, as a share of the sky that hides."""
    hidden = np.zeros_like(height)
    scales = (radius / 4, radius / 2, radius)
    for scale in scales:
        rise = np.maximum(blurred(height, scale) - height, 0.0) * depth
        hidden += np.arctan(rise / scale) / (np.pi / 2)
    return np.clip(1.0 - hidden / len(scales), 0.0, 1.0)


def _scaled(mask: np.ndarray) -> np.ndarray:
    top = float(np.percentile(mask, TOP))
    return np.clip(mask / top, 0.0, 1.0) if top > 0 else np.zeros_like(mask)
