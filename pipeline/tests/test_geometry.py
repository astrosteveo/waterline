import math

import pytest

from kiln import geometry


def test_box_is_closed_outward_and_sized():
    mesh = geometry.box((2.0, 1.0, 0.5), center=(1.0, 0.0, 0.0))
    assert mesh.open_edges() == [] and mesh.inconsistent_edges() == []
    assert mesh.signed_volume() == pytest.approx(1.0)
    assert mesh.bounds() == ((0.0, -0.5, -0.25), (2.0, 0.5, 0.25))
    assert mesh.triangle_count() == 12


def test_loft_with_caps_is_closed_and_outward():
    square = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    mesh = geometry.loft([geometry.ring(square, 0), geometry.ring(square, -3)])
    assert mesh.open_edges() == [] and mesh.inconsistent_edges() == []
    assert mesh.signed_volume() == pytest.approx(12.0)


def test_loft_turns_inward_rings_outward():
    # The same square listed the other way round still gives outward faces.
    square = [(-1, 1), (1, 1), (1, -1), (-1, -1)]
    mesh = geometry.loft([geometry.ring(square, 0), geometry.ring(square, 2)])
    assert mesh.signed_volume() == pytest.approx(8.0)


def test_loft_to_a_tip_needs_no_cap():
    square = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    mesh = geometry.loft([geometry.ring(square, 0), [(0.0, 0.0, -3.0)]])
    assert mesh.open_edges() == [] and mesh.inconsistent_edges() == []
    assert mesh.signed_volume() == pytest.approx(4.0)  # a pyramid: base 4, height 3


def test_loft_without_caps_is_open():
    square = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    mesh = geometry.loft([geometry.ring(square, 0), geometry.ring(square, 1)], caps=False)
    assert len(mesh.open_edges()) == 8


def test_loft_rejects_mismatched_rings():
    with pytest.raises(ValueError):
        geometry.loft([geometry.ring([(0, 0), (1, 0), (1, 1)], 0), geometry.ring([(0, 0), (1, 0), (1, 1), (0, 1)], 1)])


def test_lathe_cylinder_volume():
    mesh = geometry.lathe([(0, 0), (1, 0), (1, 2), (0, 2)], segments=64)
    assert mesh.open_edges() == [] and mesh.inconsistent_edges() == []
    # A 64-sided prism is within 0.2% of the cylinder.
    assert mesh.signed_volume() == pytest.approx(math.pi * 2, rel=0.002)


def test_lathe_open_profile_is_capped():
    mesh = geometry.lathe([(1, 0), (1, 1)], segments=8)
    assert mesh.open_edges() == [] and mesh.inconsistent_edges() == []
    assert mesh.signed_volume() > 0


def test_mirrored_ring_is_symmetric_without_repeating_the_centre():
    ring = geometry.mirrored_ring([(0, 0), (0.5, 0.2), (0.6, 0.8), (0, 1)], z=-1)
    assert ring == [(0, 0, -1), (0.5, 0.2, -1), (0.6, 0.8, -1), (0, 1, -1), (-0.6, 0.8, -1), (-0.5, 0.2, -1)]


def test_mirroring_keeps_faces_outward():
    mesh = geometry.box((1, 1, 1)).translated((2, 0, 0)).scaled((-1, 1, 1))
    assert mesh.signed_volume() == pytest.approx(1.0)
    assert mesh.bounds()[1][0] == pytest.approx(-1.5)


def test_merged_keeps_both():
    a, b = geometry.box((1, 1, 1)), geometry.box((1, 1, 1), center=(3, 0, 0))
    both = a.merged(b)
    assert len(both.vertices) == 16 and both.open_edges() == []
    assert both.signed_volume() == pytest.approx(2.0)


def test_loft_bands_give_each_strip_its_slot_and_caps_theirs():
    square = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    mesh = geometry.loft([geometry.ring(square, 0), geometry.ring(square, -1)], bands=[0, 1, 2, 3], cap_slot=4)
    sides, caps = mesh.slots()[:4], mesh.slots()[4:]
    assert sorted(sides) == [0, 1, 2, 3] and set(caps) == {4} and len(caps) == 8
    # The strip from point 1 (1, -1) to point 2 (1, 1) is the right side, x = 1.
    right = mesh.faces[mesh.slots().index(1)]
    assert all(mesh.vertices[i][0] == 1 for i in right)


def test_loft_rejects_the_wrong_number_of_bands():
    square = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    with pytest.raises(ValueError):
        geometry.loft([geometry.ring(square, 0), geometry.ring(square, 1)], bands=[0, 1])


def test_rotation_turns_as_godot_does():
    point = geometry.Mesh(((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, 1.0)), ((0, 1, 2),))
    # +90 degrees about X takes +Y to +Z; about Y takes +Z to +X; about Z takes +X to +Y.
    assert point.rotated("x", 90).vertices[0] == pytest.approx((0, 0, 1))
    assert point.rotated("y", 90).vertices[2] == pytest.approx((1, 0, 0))
    assert point.rotated("z", 90).vertices[1] == pytest.approx((0, 1, 0))
    with pytest.raises(ValueError):
        point.rotated("w", 90)


def test_slots_survive_moves_and_merges():
    a = geometry.box((1, 1, 1)).with_material(2)
    b = geometry.box((1, 1, 1))
    both = a.translated((1, 0, 0)).rotated("y", 30).scaled((-1, 1, 1)).merged(b)
    assert both.slots() == (2,) * 6 + (0,) * 6
    assert geometry.box((1, 1, 1)).merged(geometry.box((1, 1, 1))).materials is None
