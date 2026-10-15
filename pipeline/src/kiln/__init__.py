"""Kiln builds game assets from Python recipes in headless Blender.

A recipe is a Python file under a project's art folder with one function decorated with
`model`. Kiln runs it inside Blender, checks what it built, exports it and renders a preview
sheet. This package imports nothing from Blender at the top level, so the command line and
the tests run without it; `kiln.blender` is the part that runs inside Blender.
"""
from kiln.recipe import ModelSpec, model

__all__ = ["ModelSpec", "model"]
