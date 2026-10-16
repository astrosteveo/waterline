"""Kiln builds game assets from Python recipes.

A recipe is a Python file under a project's art folder with one function decorated with
`model`, `texture` or `sound`. Kiln runs a model or texture recipe inside Blender, checks
what it built, exports it (a model as a binary glTF, a texture as PNG maps) and renders a
preview sheet. A sound recipe runs in plain Python with numpy and scipy (`kiln.audio`), and
kiln checks its samples and writes them as WAV files. This package imports nothing from
Blender, numpy or scipy at the top level, so the command line and the tests run without
them; `kiln.blender` is the part that runs inside Blender.
"""
from kiln.recipe import ModelSpec, SoundSpec, TextureSpec, model, sound, texture

__all__ = ["ModelSpec", "SoundSpec", "TextureSpec", "model", "sound", "texture"]
