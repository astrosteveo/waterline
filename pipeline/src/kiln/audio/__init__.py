"""Kiln's sound side: the kit sound recipes build with (`SoundKit`), and the build that runs
a recipe, checks its sounds, writes them as WAV files and renders their preview sheet. It
runs in plain Python with numpy and scipy, without Blender."""
from kiln.audio.kit import SoundKit

__all__ = ["SoundKit"]
