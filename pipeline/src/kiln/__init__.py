"""Kiln builds game assets from Python recipes in headless Blender.

A recipe is a Python file under a project's art folder with one function decorated with
`model` or `texture`. Kiln runs it inside Blender, checks what it built, exports it (a model
as a binary glTF, a texture as PNG maps) and renders a preview sheet. This package imports
nothing from Blender at the top level, so the command line and the tests run without it;
`kiln.blender` is the part that runs inside Blender.
"""
from kiln.recipe import ModelSpec, TextureSpec, model, texture

__all__ = ["ModelSpec", "TextureSpec", "model", "texture"]
