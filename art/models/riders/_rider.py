"""The rider every rider is built from: one figure with the build and gear as parameters.

The game poses a rider by turning the bones of its skeleton between joints
(godot/jetski/model/jetski_model.gd). The rider is built as a set of parts, each a named
object with the objects built under it, and a part's meshes are skinned to the bone of the
same name (Rider.bones), which the game finds by name; a limb's skin blends into the next
part's bone toward each joint (Rider.skin_weights), so the suit bends round the joint. The
part's own mesh is named for it, with Mesh after (TorsoMesh):

- Torso: the suit from the seat to the neck, the life vest and its straps. Turns with the spine.
- Head: the neck and head, the helmet and visor, goggles and hair. Turns with the spine.
- ThighLeft, ShinLeft, UpperArmLeft, ForearmLeft (and Right): each runs from one joint to the
  next (hip to knee, knee to foot, shoulder to elbow, elbow to hand). The game bends the knees
  and elbows to keep each the length it is here, and stretches one only to reach further.
- BootLeft, GloveLeft (and Right): at the foot and at the hand.

The figure is built seated in the riding pose the game starts from, on the Tradewind with the
controls centred, with the pelvis at the origin, facing -Z. Markers named Pelvis, HipLeft,
KneeLeft, FootLeft, ShoulderLeft, ElbowLeft and HandLeft (and Right) mark the joints: the game
takes the rider's hip and shoulder width and the length of the back and of each limb from them,
and each part's place on its joints. The joints follow JetSkiModel._riding_joints(), so a rider
on the Tradewind draws as built; on another craft the hands and feet move to its handlebar and
footrests.

White and light grey suit, vest and helmet materials (named Suit..., Vest..., Helmet...) are
painted in the rider's colours in the game; every other material keeps its own colour.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from kiln import geometry

from models.craft._jetski import GRIP_SPREAD, JetSki

Vec3 = tuple[float, float, float]

# The joints JetSkiModel._riding_joints() puts above the pelvis, for a back of length 1.
CHEST = (0.0, 0.46, -0.24)
HEAD = (0.0, 0.74, -0.33)
# The base rider's limbs: hip to knee, knee to the sole, shoulder to elbow, elbow to the middle
# of the grip.
THIGH = 0.44
SHIN = 0.47
UPPER_ARM = 0.34
FOREARM = 0.33
# Which way it bends the knees and elbows (for the left side; x flips for the right): the knees
# forward and out, the elbows out, down and back.
KNEE_OUT = (0.12, 0.0, -0.24)
ELBOW_OUT = (0.12, -0.06, 0.06)

# How far either side of a joint a limb's skin blends from its bone into the next part's, in
# metres: the suit bends round the joint instead of folding at a seam. Half on each bone at
# the joint, all on its own a blend's width away. The neck needs none: the head turns with
# the spine, as the torso does.
BLEND = {"hip": 0.06, "knee": 0.07, "ankle": 0.03, "shoulder": 0.05, "elbow": 0.06, "wrist": 0.03}

# Gear colours. Painted parts are white or light grey; the game multiplies in the rider's
# suit, vest or helmet colour.
PAINT = "#ffffff"
PAINT_SHADE = "#c4c4c4"
STRAP = "#1b1d21"
BUCKLE = "#8d939b"
VISOR = "#12161c"
GLOVE = "#202228"
BOOT = "#26282d"
SOLE = "#0d0e10"

SIDES = (("Left", -1.0), ("Right", 1.0))
JOINTS = ["Pelvis"] + [f"{joint}{side}" for side, _ in SIDES
                       for joint in ("Hip", "Knee", "Foot", "Shoulder", "Elbow", "Hand")]
# The materials the game paints in the rider's suit, vest and helmet colours (it matches the
# start of a name, so SuitShade is painted too).
PAINTED = ["Suit", "Vest", "Helmet"]
# The bones at the knees and elbows that the game turns halfway between the limbs meeting
# there. The skin round the joint follows them, so a straightened knee keeps its width:
# blended straight from the thigh to the shin, it would narrow (by cos 45° for a 90° turn).
BENDS = [f"{joint}Bend{side}" for side, _ in SIDES for joint in ("Knee", "Elbow")]
# The parts the game poses; each recipe's build must make all of them.
PARTS = ["Torso", "Head"] + [f"{part}{side}" for side, _ in SIDES
                             for part in ("Thigh", "Shin", "Boot", "UpperArm", "Forearm", "Glove")]


@dataclass(frozen=True)
class Rider:
    """A rider's build and gear. Lengths in metres."""

    # Half the width between the shoulder joints, and between the hip joints.
    shoulder_half: float = 0.21
    hip_half: float = 0.11
    # The back's length (pelvis to shoulders and head) as a share of the base rider's.
    back: float = 1.0
    # The arms' and legs' length as a share of the base rider's.
    limbs: float = 1.0
    # How thick the body and limbs are, as a share of the base rider's.
    girth: float = 1.0
    skin: str = "#c99574"
    # "full" (a full-face helmet and visor), "peak" (full-face with a peak over the visor) or
    # "open" (an open-face helmet and goggles).
    helmet: str = "full"
    # "full" (long sleeves and legs) or "shorty" (bare forearms and shins).
    suit: str = "full"
    # "standard", "bulky" (thicker, with a high collar) or "slim".
    vest: str = "standard"
    # A ponytail's colour, or None for none.
    ponytail: str | None = None

    # --- Joints ---------------------------------------------------------------------

    def joints(self, ski: JetSki = JetSki()) -> dict[str, Vec3]:
        """Each joint in the riding pose on `ski` with the controls centred, the pelvis at
        the origin (where the craft's Seat marker is)."""
        seat = ski.seat_marker()
        foot_x, foot_z = ski.footrest()
        foot_y = ski.deck(0.5) + 0.03
        chest = _scale(CHEST, self.back)
        joints = {"Pelvis": (0.0, 0.0, 0.0)}
        for side, s in SIDES:
            hip = (self.hip_half * s, 0.0, 0.0)
            shoulder = _add(chest, (self.shoulder_half * s, 0.0, 0.0))
            foot = _sub((foot_x * s, foot_y, foot_z), seat)
            hand = _sub((GRIP_SPREAD * s, ski.bar_height, ski.z(ski.bar_at)), seat)
            joints[f"Hip{side}"] = hip
            joints[f"Knee{side}"] = _bend(hip, foot, THIGH * self.limbs, SHIN * self.limbs,
                                          _mul(KNEE_OUT, (s, 1, 1)))
            joints[f"Foot{side}"] = foot
            joints[f"Shoulder{side}"] = shoulder
            joints[f"Elbow{side}"] = _bend(shoulder, hand, UPPER_ARM * self.limbs, FOREARM * self.limbs,
                                           _mul(ELBOW_OUT, (s, 1, 1)))
            joints[f"Hand{side}"] = hand
        return joints

    def bones(self) -> dict[str, tuple[Vec3, Vec3]]:
        """A bone for each part, from the joint it hangs from toward the next, named as the
        part: the torso from the pelvis to the chest, the head from the neck to the head's
        centre, each limb from joint to joint, a boot forward from the foot and a glove out
        from the hand; and a bend bone at each knee and elbow (BENDS), pointing between the
        limbs meeting there."""
        joints = self.joints()
        bones = {"Torso": (joints["Pelvis"], _scale(CHEST, self.back)),
                 "Head": (_scale(self.spine_axis(), 0.6 * self.back), self.head())}
        for side, s in SIDES:
            hip, knee, foot = joints[f"Hip{side}"], joints[f"Knee{side}"], joints[f"Foot{side}"]
            shoulder, elbow, hand = joints[f"Shoulder{side}"], joints[f"Elbow{side}"], joints[f"Hand{side}"]
            bones[f"Thigh{side}"] = (hip, knee)
            bones[f"Shin{side}"] = (knee, foot)
            bones[f"Boot{side}"] = (foot, _add(foot, (0.0, 0.0, -0.15)))
            bones[f"UpperArm{side}"] = (shoulder, elbow)
            bones[f"Forearm{side}"] = (elbow, hand)
            bones[f"Glove{side}"] = (hand, _add(hand, (0.08 * s, 0.0, 0.0)))
            for joint, before, after in (("Knee", hip, foot), ("Elbow", shoulder, hand)):
                at = joints[f"{joint}{side}"]
                between = _normalized(_add(_normalized(_sub(at, before)), _normalized(_sub(after, at))))
                bones[f"{joint}Bend{side}"] = (at, _add(at, _scale(between, 0.08)))
        return bones

    def skin_weights(self) -> dict:
        """How each part's meshes follow the bones, for `Kit.skin`: a limb's from its own
        bone into the next part's toward each end (see BLEND), through the bend bone at a
        knee or elbow; the torso, head, boots and gloves wholly on their own."""
        joints = self.joints()
        weights: dict = {part: part for part in ("Torso", "Head")}
        for side, _ in SIDES:
            hip, knee, foot = joints[f"Hip{side}"], joints[f"Knee{side}"], joints[f"Foot{side}"]
            shoulder, elbow, hand = joints[f"Shoulder{side}"], joints[f"Elbow{side}"], joints[f"Hand{side}"]
            knee_bend, elbow_bend = f"KneeBend{side}", f"ElbowBend{side}"
            weights[f"Thigh{side}"] = _blended(f"Thigh{side}", hip, knee, ("Torso", None, BLEND["hip"]),
                                               (f"Shin{side}", knee_bend, BLEND["knee"]))
            weights[f"Shin{side}"] = _blended(f"Shin{side}", knee, foot, (f"Thigh{side}", knee_bend, BLEND["knee"]),
                                              (f"Boot{side}", None, BLEND["ankle"]))
            weights[f"UpperArm{side}"] = _blended(f"UpperArm{side}", shoulder, elbow,
                                                  ("Torso", None, BLEND["shoulder"]),
                                                  (f"Forearm{side}", elbow_bend, BLEND["elbow"]))
            weights[f"Forearm{side}"] = _blended(f"Forearm{side}", elbow, hand,
                                                 (f"UpperArm{side}", elbow_bend, BLEND["elbow"]),
                                                 (f"Glove{side}", None, BLEND["wrist"]))
            weights[f"Boot{side}"] = f"Boot{side}"
            weights[f"Glove{side}"] = f"Glove{side}"
        return weights

    def head(self) -> Vec3:
        """The centre of the head, which the head and helmet are built round."""
        return _scale(HEAD, self.back)

    def spine_axis(self) -> Vec3:
        """Up the back, from the pelvis toward the shoulders."""
        return _normalized(CHEST)


def build(k, rider: Rider) -> None:
    """Builds `rider` into the kit `k`."""
    suit = k.material("Suit", PAINT, roughness=0.8)
    shade = k.material("SuitShade", PAINT_SHADE, roughness=0.8)
    vest = k.material("Vest", PAINT, roughness=0.65)
    helmet = k.material("Helmet", PAINT, roughness=0.25)
    skin = k.material("Skin", rider.skin, roughness=0.6)
    strap = k.material("Strap", STRAP, roughness=0.7)
    buckle = k.material("Buckle", BUCKLE, roughness=0.35, metallic=0.6)
    visor = k.material("Visor", VISOR, roughness=0.08, metallic=0.4)
    glove = k.material("Glove", GLOVE, roughness=0.75)
    boot = k.material("Boot", BOOT, roughness=0.7)
    sole = k.material("Sole", SOLE, roughness=0.9)

    joints = rider.joints()
    for name, at in joints.items():
        k.marker(name, at)
    g = rider.girth

    # --- Torso, vest and straps ---------------------------------------------------------
    up = rider.spine_axis()
    back = _cross((1.0, 0.0, 0.0), up)
    b = rider.back
    sh, hp = rider.shoulder_half, rider.hip_half
    # (height up the back, half width, half depth in front, half depth behind)
    torso_rings = [
        (-0.1, hp + 0.0, 0.05 * g, 0.06 * g),
        (-0.06, hp + 0.05 * g, 0.09 * g, 0.105 * g),
        (0.02, hp + 0.07 * g, 0.105 * g, 0.12 * g),
        (0.15, hp + 0.045 * g, 0.1 * g, 0.105 * g),
        (0.31, sh, 0.125 * g, 0.115 * g),
        (0.45, sh + 0.035 * g, 0.105 * g, 0.105 * g),
        (0.535, sh - 0.02, 0.09 * g, 0.09 * g),
        # The slope from the shoulders up to the neck.
        (0.6, 0.12 * g, 0.07 * g, 0.075 * g),
        (0.655, 0.065 * g, 0.055 * g, 0.06 * g),
    ]
    torso = k.mesh("Torso", _body_loft(torso_rings, up, back, b, 14), suit, smooth_angle=60)

    thick = {"standard": 1.0, "bulky": 1.45, "slim": 0.75}[rider.vest]
    t = 0.03 * thick
    vest_rings = [
        (0.04, hp + 0.07 * g + t, 0.1 * g + t, 0.115 * g + t),
        (0.15, hp + 0.045 * g + t, 0.1 * g + t, 0.105 * g + t),
        (0.31, sh - 0.01 + t * 0.5, 0.125 * g + t, 0.115 * g + t),
        (0.45, sh - 0.045, 0.105 * g + t, 0.105 * g + t),
        (0.535, 0.12 * g + t, 0.085 * g + t, 0.085 * g + t),
    ]
    if rider.vest == "bulky":
        # A high collar round the back of the neck.
        vest_rings.append((0.63, 0.1 * g + t, 0.07 * g + t * 0.5, 0.08 * g + t))
    if rider.vest == "slim":
        vest_rings = vest_rings[1:]
    k.mesh("Vest", _body_loft(vest_rings, up, back, b, 14), vest, parent=torso, smooth_angle=50)
    strap_heights = {"standard": (0.17, 0.29), "bulky": (0.13, 0.25, 0.37), "slim": (0.22,)}[rider.vest]
    for i, h in enumerate(strap_heights):
        w, front, rear = _ring_size(vest_rings, h)
        rings = [(h - 0.018, w + 0.007, front + 0.007, rear + 0.007),
                 (h + 0.018, w + 0.007, front + 0.007, rear + 0.007)]
        k.mesh(f"Strap{i + 1}", _body_loft(rings, up, back, b, 14), strap, parent=torso, smooth_angle=50)
        centre = _add(_scale(up, h * b), _scale(back, -(front + 0.012)))
        clasp = geometry.box((0.06, 0.035, 0.016)).rotated("x", -math.degrees(math.atan2(-up[2], up[1])))
        k.mesh(f"Buckle{i + 1}", clasp, buckle, parent=torso, position=centre)

    # --- Head, helmet and gear ----------------------------------------------------------
    head_at = rider.head()
    neck_from = _scale(up, 0.6 * b)
    neck = _limb(neck_from, head_at, [(0.0, 0.058 * g), (0.75, 0.052 * g)], 10, tips=False)
    skull = geometry.lathe([(0, -0.115), (0.06, -0.105), (0.088, -0.07), (0.1, -0.02), (0.1, 0.03),
                            (0.085, 0.075), (0.05, 0.105), (0, 0.115)], 12).scaled((1.0, 1.0, 1.1))
    head = k.mesh("Head", skull, skin, position=head_at, smooth_angle=70)
    k.mesh("Neck", neck.translated(_neg(head_at)), skin, parent=head, position=head_at, smooth_angle=70)
    if rider.helmet == "open":
        _open_helmet(k, head, head_at, helmet, strap, visor)
    else:
        _full_helmet(k, head, head_at, helmet, visor, peak=rider.helmet == "peak")
    if rider.ponytail:
        hair = k.material("Hair", rider.ponytail, roughness=0.85)
        path = [(0.0, -0.01, 0.135), (0.0, -0.06, 0.19), (0.0, -0.14, 0.215), (0.0, -0.22, 0.2)]
        k.mesh("Ponytail", _tube([_add(head_at, p) for p in path], [0.035, 0.036, 0.026, 0.0], 8)
               .translated(_neg(head_at)), hair, parent=head, position=head_at, smooth_angle=60)

    # --- Limbs --------------------------------------------------------------------------
    bare = rider.suit == "shorty"
    for side, s in SIDES:
        hip, knee, foot = joints[f"Hip{side}"], joints[f"Knee{side}"], joints[f"Foot{side}"]
        shoulder, elbow, hand = joints[f"Shoulder{side}"], joints[f"Elbow{side}"], joints[f"Hand{side}"]
        # At the knee and the elbow the upper part is the thicker, so its rounded end covers
        # the lower part's.
        _limb_part(k, f"Thigh{side}", hip, knee, [(-0.06, 0.095 * g), (0.15, 0.1 * g), (1.0, 0.07 * g)], suit)
        _limb_part(k, f"Shin{side}", knee, foot, [(0.03, 0.056 * g), (0.25, 0.064 * g), (0.92, 0.045 * g)],
                   skin if bare else shade)
        _limb_part(k, f"UpperArm{side}", shoulder, elbow, [(0.0, 0.064 * g), (0.3, 0.062 * g), (1.0, 0.052 * g)],
                   suit)
        _limb_part(k, f"Forearm{side}", elbow, hand, [(0.03, 0.043 * g), (0.3, 0.05 * g), (0.82, 0.037 * g)],
                   skin if bare else shade)
        if bare:
            # The shorty's legs and sleeves end in a cuff above the knee and the elbow.
            _limb_part(k, f"Cuff{side}", hip, knee, [(0.72, 0.08 * g), (0.86, 0.077 * g)], suit, tips=False,
                       parent=f"Thigh{side}")
            _limb_part(k, f"Sleeve{side}", shoulder, elbow, [(0.0, 0.07 * g), (0.55, 0.067 * g)], suit, tips=False,
                       parent=f"UpperArm{side}")
        _boot(k, f"Boot{side}", foot, g, boot, sole)
        _glove(k, f"Glove{side}", hand, s, g, glove)

    # --- Skeleton -----------------------------------------------------------------------
    skeleton = k.armature("Skeleton", rider.bones())
    weights = rider.skin_weights()
    for part in PARTS:
        root = k.collection.objects[part]
        # The bone has the part's name. A glTF bone is a node too, and the game's importer
        # renames one of two nodes with one name, so the part's own mesh takes another.
        root.name = part + "Mesh"
        for obj in [root, *root.children_recursive]:
            if obj.type == "MESH":
                k.skin(obj, skeleton, weights[part])


# --- Parts ------------------------------------------------------------------------------

def _limb_part(k, name, a, b, profile, material, tips=True, parent=None):
    mesh = _limb(a, b, profile, 10, tips)
    parent_obj = k.collection.objects.get(parent) if parent else None
    return k.mesh(name, mesh.translated(_neg(a)), material, parent=parent_obj, position=a, smooth_angle=65)


def _full_helmet(k, head, at, paint, visor, peak):
    """A full-face helmet: a rounded shell round the head with a chin bar, and a dark visor
    across the front; with `peak`, a motocross peak over the visor."""
    profile = [(0.0, -0.15), (0.095, -0.15), (0.13, -0.115), (0.152, -0.04), (0.155, 0.02), (0.145, 0.07),
               (0.12, 0.115), (0.075, 0.148), (0.0, 0.16)]
    shell = geometry.lathe(profile, 16).scaled((1.0, 1.0, 1.1)).translated((0.0, 0.02, 0.0))
    k.mesh("Helmet", shell, paint, parent=head, position=at, smooth_angle=60)
    radius = _profile_radius(profile)
    band = _front_band(lambda y: radius(y - 0.02), -0.03, 0.045, 68, 0.004, 0.012, 1.1)
    k.mesh("Visor", band, visor, parent=head, position=at, smooth_angle=60)
    if peak:
        brim = _front_band(lambda y: radius(y - 0.02), 0.085, 0.1, 55, -0.01, 0.075, 1.1, droop=0.02)
        k.mesh("Peak", brim, paint, parent=head, position=at, smooth_angle=35)


def _open_helmet(k, head, at, paint, strap, lens):
    """An open-face helmet: a dome over the top and back of the head, tipped up at the front,
    and goggles across the eyes on a strap round the helmet."""
    profile = [(0.0, -0.005), (0.14, -0.005), (0.148, 0.04), (0.138, 0.085), (0.11, 0.125), (0.065, 0.15),
               (0.0, 0.158)]
    dome = geometry.lathe(profile, 16).scaled((1.0, 1.0, 1.1)).rotated("x", 14).translated((0.0, 0.015, 0.012))
    k.mesh("Helmet", dome, paint, parent=head, position=at, smooth_angle=60)
    k.mesh("GoggleStrap", geometry.lathe([(0, -0.012), (0.152, -0.012), (0.152, 0.018), (0, 0.018)], 16)
           .scaled((1.0, 1.0, 1.1)).rotated("x", 14).translated((0.0, 0.024, 0.012)),
           strap, parent=head, position=at, smooth_angle=60)
    face = _profile_radius([(0.06, -0.105), (0.088, -0.07), (0.1, -0.02), (0.1, 0.03), (0.085, 0.075)])
    k.mesh("Goggles", _front_band(face, -0.005, 0.04, 58, 0.012, 0.03, 1.1), lens, parent=head,
           position=at, smooth_angle=50)


def _boot(k, name, foot, g, boot, sole):
    """A boot under the foot joint: an ankle collar at the heel, a low toe out in front. The
    shin comes down into the collar."""
    w = 0.052 * g
    # (z along the foot, half width, sole height, top height); +z toward the heel.
    stations = [(0.085, 0.75, -0.012, 0.09), (0.055, 0.95, -0.014, 0.125), (0.0, 1.0, -0.014, 0.11),
                (-0.07, 1.02, -0.014, 0.07), (-0.14, 0.95, -0.014, 0.05), (-0.185, 0.75, -0.01, 0.035)]
    sections = []
    for z, wf, low, high in stations:
        half = [(0.0, low), (w * wf * 0.9, low), (w * wf, low + 0.02), (w * wf, (low + high) / 2),
                (w * wf * 0.75, high), (0.0, high + 0.004)]
        sections.append(geometry.mirrored_ring(half, z))
    sections.append([(0.0, 0.0, -0.205)])
    # The sole: the strips along the bottom, from the edge on one side to the other.
    bands = [1, 1, 0, 0, 0, 0, 0, 0, 1, 1]
    k.mesh(name, geometry.loft(sections, bands=bands, cap_slot=0), [boot, sole], position=foot, smooth_angle=50)


def _glove(k, name, hand, side, g, material):
    """A fist round the grip: the bar runs through it along X, the thumb wraps over the top."""
    fist = geometry.lathe([(0.0, -0.045), (0.036, -0.044), (0.046, -0.025), (0.047, 0.025), (0.036, 0.044),
                           (0.0, 0.045)], 10).scaled((1.0, 1.0, 1.1)).rotated("z", 90)
    obj = k.mesh(name, fist.scaled((g, g, g)).translated((0.0, 0.006, 0.008)), material, position=hand,
                 smooth_angle=60)
    thumb = _tube([(-0.02 * side, 0.03, -0.035), (0.0, 0.045, -0.02), (0.012 * side, 0.048, 0.005)],
                  [0.016, 0.015, 0.0], 6)
    k.mesh(f"{name}Thumb", thumb, material, parent=obj, position=hand, smooth_angle=60)
    return obj


# --- Shapes -----------------------------------------------------------------------------

def _body_loft(rings, up, back, length_scale, n):
    """A loft up the back: each ring (height, half width, half depth in front, behind)
    square to `up`, at that height times `length_scale`."""
    x = (1.0, 0.0, 0.0)
    sections = []
    for h, w, front, rear in rings:
        c = _scale(up, h * length_scale)
        ring = []
        for i in range(n):
            a = math.tau * i / n
            depth = rear if math.sin(a) > 0 else front
            ring.append(_add(c, _add(_scale(x, w * math.cos(a)), _scale(back, depth * math.sin(a)))))
        sections.append(ring)
    return geometry.loft(sections)


def _ring_size(rings, h):
    """The (half width, front, rear) of a body loft at height `h`, between its rings."""
    for (h0, *a), (h1, *b) in zip(rings, rings[1:]):
        if h0 <= h <= h1:
            u = (h - h0) / (h1 - h0)
            return tuple(p + (q - p) * u for p, q in zip(a, b))
    return tuple(rings[-1][1:])


def _limb(a, b, profile, n, tips=True):
    """A round limb along a→b: rings square to it at (share of the length, radius); with
    `tips`, rounded ends past the first and last ring."""
    axis = _sub(b, a)
    length = _length(axis)
    y = _scale(axis, 1 / length)
    x, z = _across(y)

    def ring(d, r):
        c = _add(a, _scale(y, d))
        return [_add(c, _add(_scale(x, r * math.cos(math.tau * i / n)), _scale(z, r * math.sin(math.tau * i / n))))
                for i in range(n)]

    sections = []
    first_d, first_r = profile[0][0] * length, profile[0][1]
    last_d, last_r = profile[-1][0] * length, profile[-1][1]
    if tips:
        sections.append([_add(a, _scale(y, first_d - first_r * 0.95))])
        sections.append(ring(first_d - first_r * 0.62, first_r * 0.78))
    sections.extend(ring(t * length, r) for t, r in profile)
    if tips:
        sections.append(ring(last_d + last_r * 0.62, last_r * 0.78))
        sections.append([_add(a, _scale(y, last_d + last_r * 0.95))])
    return geometry.loft(sections)


def _tube(path, radii, n):
    """A tube along `path` with a radius per point; a radius of 0 is a tip."""
    sections = []
    for i, (p, r) in enumerate(zip(path, radii)):
        if r <= 0:
            sections.append([p])
            continue
        ahead = path[min(i + 1, len(path) - 1)]
        behind = path[max(i - 1, 0)]
        x, z = _across(_normalized(_sub(ahead, behind)))
        sections.append([_add(p, _add(_scale(x, r * math.cos(math.tau * j / n)), _scale(z, r * math.sin(math.tau * j / n))))
                         for j in range(n)])
    return geometry.loft(sections)


def _front_band(radius, y0, y1, half_angle, gap, thickness, z_scale, droop=0.0):
    """A curved plate across the front of a round shape, from height `y0` to `y1` and
    `half_angle` degrees either side of straight ahead, standing `gap` off the surface whose
    radius at a height is `radius(y)`; `droop` lowers its outer edge."""
    sections = []
    steps = 8
    for i in range(steps + 1):
        a = math.radians(-half_angle + 2 * half_angle * i / steps)
        ring = []
        for y, out in ((y0, 0.0), (y0, 1.0), (y1, 1.0), (y1, 0.0)):
            r = radius(y) + gap + thickness * out
            ring.append((r * math.sin(a), y - droop * out, -r * math.cos(a) * z_scale))
        sections.append(ring)
    return geometry.loft(sections)


def _profile_radius(profile):
    """The radius of a lathe profile at a height, between its points."""
    def radius(y):
        for (r0, y0), (r1, y1) in zip(profile, profile[1:]):
            if y0 <= y <= y1 and y1 > y0:
                return r0 + (r1 - r0) * (y - y0) / (y1 - y0)
        return profile[0][0] if y < profile[0][1] else profile[-1][0]
    return radius


# --- Joints -----------------------------------------------------------------------------

def _bend(a, b, length_a, length_b, pole):
    """Where a knee or an elbow goes, as JetSkiModel._bend() puts it: `length_a` from `a` (the
    hip or shoulder) and `length_b` from `b` (the foot or hand), bent toward `pole`. A limb too
    short to reach is straight, and stretched evenly along its two parts."""
    axis = _sub(b, a)
    reach = _length(axis)
    along_axis = _scale(axis, 1 / reach)
    d = min(max(reach, abs(length_a - length_b) + 0.001), length_a + length_b)
    along = (length_a * length_a - length_b * length_b + d * d) / (2 * d)
    out = math.sqrt(max(length_a * length_a - along * along, 0.0))
    side = _sub(pole, _scale(along_axis, _dot(pole, along_axis)))
    return _add(_add(a, _scale(along_axis, along * reach / d)), _scale(_normalized(side), out))


# --- Vectors ----------------------------------------------------------------------------

def _blended(bone: str, start: Vec3, end: Vec3, before: tuple, after: tuple):
    """Skin weights for a limb's bone running from `start` to `end`. `before` and `after` say
    how its skin blends at each end, measured along the limb: (the next part's bone, the
    bend bone at the joint or None, the blend's width). Without a bend bone the skin is half
    on each bone at the joint; with one it is wholly on the bend bone there, and blends from
    it into each limb's own over the width."""
    axis = _normalized(_sub(end, start))

    def weights(p: Vec3) -> dict[str, float]:
        amounts = {bone: 1.0}
        for joint, outward, (other, bend, width) in ((start, -1.0, before), (end, 1.0, after)):
            # How far past the joint, toward the other part.
            past = outward * _dot(_sub(p, joint), axis)
            if bend is None:
                share = _smoothstep(-width, width, past)
                amounts[other] = amounts.get(other, 0.0) + share
            else:
                share = _smoothstep(-width, 0.0, past)
                beyond = _smoothstep(0.0, width, past)
                amounts[other] = amounts.get(other, 0.0) + beyond
                amounts[bend] = amounts.get(bend, 0.0) + share - beyond
            amounts[bone] -= share
        return {name: max(0.0, amount) for name, amount in amounts.items()}

    return weights


def _smoothstep(low: float, high: float, x: float) -> float:
    t = min(max((x - low) / (high - low), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _neg(a):
    return (-a[0], -a[1], -a[2])


def _scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _mul(a, b):
    return (a[0] * b[0], a[1] * b[1], a[2] * b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _length(a):
    return math.sqrt(_dot(a, a))


def _normalized(a):
    return _scale(a, 1 / _length(a))


def _across(y):
    """Two directions square to `y` and to each other: the first as close to +X as it can be."""
    ref = (1.0, 0.0, 0.0) if abs(y[0]) < 0.9 else (0.0, 0.0, -1.0)
    x = _normalized(_sub(ref, _scale(y, _dot(ref, y))))
    return x, _cross(x, y)
