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


# --- UVs ------------------------------------------------------------------------------------

def uv_signed_area(corners):
    """A face's area in UV space, positive when its corners run counter-clockwise there."""
    return sum(corners[i][0] * corners[(i + 1) % len(corners)][1] - corners[(i + 1) % len(corners)][0] * corners[i][1]
               for i in range(len(corners))) / 2


def face_area(mesh, face):
    points = [mesh.vertices[i] for i in face]
    return math.hypot(*geometry._newell(points)) / 2


def assert_uvs_read_right_way_round(mesh):
    """Every face's UVs run counter-clockwise, as its corners do seen from outside, so a
    texture isn't mirrored."""
    assert mesh.uvs is not None
    for corners in mesh.uvs:
        assert uv_signed_area(corners) > 0


def test_box_faces_each_have_their_size_in_uvs():
    mesh = geometry.box((2.0, 1.0, 0.5), center=(5.0, 0.0, 0.0))
    assert_uvs_read_right_way_round(mesh)
    for face, corners in zip(mesh.faces, mesh.uvs):
        assert uv_signed_area(corners) == pytest.approx(face_area(mesh, face))
    # On the sides v runs up: the +X face is the box's depth (0.5) across and its height (1) up.
    side = next(c for f, c in zip(mesh.faces, mesh.uvs) if all(mesh.vertices[i][0] == 6.0 for i in f))
    assert sorted({u for u, _ in side}) == pytest.approx([-0.25, 0.25])
    assert sorted({v for _, v in side}) == pytest.approx([-0.5, 0.5])
    # They are the box's projection, so a bevelled box, projected again, agrees on its flats.
    assert mesh.uvs == geometry.Mesh(mesh.vertices, mesh.faces).projected().uvs


def test_lathe_uvs_are_metres_round_and_up_the_profile():
    segments = 64
    mesh = geometry.lathe([(0, 0), (1, 0), (1, 2), (0, 2)], segments=segments)
    assert_uvs_read_right_way_round(mesh)
    # A prism's sides unroll flat, so each side face's UVs cover exactly its area. The ends,
    # fans round the poles, are mapped out from the pole by the distance to the ring's corners,
    # so they cover a little more: the ring's corners are further out than its edges.
    for face, corners in zip(mesh.faces, mesh.uvs):
        stretch = 1.0 if len(face) == 4 else 1 / math.cos(math.pi / segments)
        assert uv_signed_area(corners) == pytest.approx(face_area(mesh, face) * stretch)
    us = [u for corners in mesh.uvs for u, _ in corners]
    vs = [v for corners in mesh.uvs for _, v in corners]
    # Round: the polygon's perimeter. Up: out along the bottom, up the side, in along the top.
    assert max(us) - min(us) == pytest.approx(segments * 2 * math.sin(math.pi / segments))
    assert (min(vs), max(vs)) == pytest.approx((0.0, 4.0))


@pytest.mark.parametrize("square", [[(-1, -1), (1, -1), (1, 1), (-1, 1)], [(-1, 1), (1, 1), (1, -1), (-1, -1)]])
def test_loft_uvs_read_right_way_round_either_way_round(square):
    mesh = geometry.loft([geometry.ring(square, 0), geometry.ring(square, -3)])
    assert_uvs_read_right_way_round(mesh)
    capped = [c for c in mesh.uvs if len(c) == 3]
    assert sum(uv_signed_area(c) for c in capped) == pytest.approx(8.0)  # two 2 x 2 caps
    tip = geometry.loft([geometry.ring(square, 0), [(0.0, 0.0, -3.0)]])
    assert_uvs_read_right_way_round(tip)


def test_loft_with_a_tip_in_the_middle_takes_each_side_from_its_own_ring():
    small = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    big = [(-2, -2), (2, -2), (2, 2), (-2, 2)]
    mesh = geometry.loft([geometry.ring(small, 0), [(0.0, 0.0, -1.0)], geometry.ring(big, -2)], caps=False)
    # u runs round each ring by the rings' mean length round (8 and 16: 12). The tip's corners
    # sit halfway along the edge of the ring each face joins.
    first, second = mesh.uvs[:4], mesh.uvs[4:]
    assert sorted(abs(c[2][0]) for c in first) == pytest.approx([1.5, 4.5, 7.5, 10.5])
    assert sorted(abs(c[0][0]) for c in second) == pytest.approx([1.5, 4.5, 7.5, 10.5])
    assert max(abs(u) for c in mesh.uvs for u, _ in c) == pytest.approx(12.0)


def test_loft_uvs_squeeze_round_a_narrower_ring_rather_than_shear():
    # A cone frustum: every side face's corners share their u with the ring below, so its
    # UVs are an upright rectangle, not a parallelogram leaning more the further round.
    mesh = geometry.lathe([(1, 0), (0.5, 1)], segments=16)
    for face, corners in zip(mesh.faces, mesh.uvs):
        if len(face) == 4:
            us = sorted(round(u, 9) for u, _ in corners)
            assert us[0] == us[1] and us[2] == us[3]


def test_transforms_keep_uvs_and_mirroring_keeps_each_corners():
    mesh = geometry.box((1.0, 2.0, 3.0))
    assert mesh.translated((1, 2, 3)).uvs == mesh.uvs
    assert mesh.rotated("y", 30).uvs == mesh.uvs
    assert mesh.scaled((2, 2, 2)).uvs == mesh.uvs
    assert mesh.with_material(1).uvs == mesh.uvs and mesh.with_materials([1] * 6).uvs == mesh.uvs
    mirrored = mesh.scaled((-1, 1, 1))
    for face, corners, old_face, old_corners in zip(mirrored.faces, mirrored.uvs, mesh.faces, mesh.uvs):
        assert dict(zip(face, corners)) == dict(zip(old_face, old_corners))


def test_merged_projects_a_mesh_without_uvs():
    plain = geometry.Mesh(geometry.box((1, 1, 1)).vertices, geometry.box((1, 1, 1)).faces)
    assert plain.merged(plain).uvs is None
    both = geometry.box((1, 1, 1)).merged(plain.translated((3, 0, 0)))
    assert both.uvs[:6] == geometry.box((1, 1, 1)).uvs
    assert both.uvs[6:] == plain.translated((3, 0, 0)).projected().uvs
    assert geometry.Mesh((), ()).merged(geometry.box((1, 1, 1))).uvs == geometry.box((1, 1, 1)).uvs


def test_projection_joins_faces_that_face_the_same_way():
    # A 2 x 1 floor of two squares, facing up: one UV for each shared vertex.
    floor = geometry.Mesh(((0, 0, 0), (1, 0, 0), (2, 0, 0), (0, 0, -1), (1, 0, -1), (2, 0, -1)),
                          ((0, 1, 4, 3), (1, 2, 5, 4))).projected()
    assert_uvs_read_right_way_round(floor)
    at = {}
    for face, corners in zip(floor.faces, floor.uvs):
        for vertex, uv in zip(face, corners):
            assert at.setdefault(vertex, uv) == uv
    # Seen from above, u runs toward +X and v forward (-Z), in metres.
    assert at[5] == pytest.approx((2.0, 1.0))
    plain = geometry.Mesh(geometry.box((1, 1, 1)).vertices, geometry.box((1, 1, 1)).faces)
    assert_uvs_read_right_way_round(plain.projected())


def test_uvs_need_one_per_corner():
    with pytest.raises(ValueError):
        geometry.Mesh(((0, 0, 0), (1, 0, 0), (0, 1, 0)), ((0, 1, 2),), uvs=(((0, 0), (1, 0)),))
