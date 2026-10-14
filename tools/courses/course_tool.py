"""Lays out a course from a JSON spec: draws a top-down map and writes the course scene.

    python3 tools/courses/course_tool.py tools/courses/gull_cove.json --map captures/gull_cove_map.png
    python3 tools/courses/course_tool.py tools/courses/gull_cove.json --scene   # the .tscn and .course.tres
    python3 tools/courses/course_tool.py tools/courses/gull_cove.json --thumb   # the menu map

The spec gives the course's id, name, conditions line and menu order (for the menus), the
centre line's control points [x, z, half width] (clockwise or not, in order of travel), buoys,
ramps and rocks by [offset along the course from the start line, meters right of the centre
line, ...], and terrain islands [x, z, radius, peak height]. The
centre line is the same centripetal Catmull-Rom curve the game builds (course/course.gd), so
offsets here match offsets in the game. The map shows the walls (with the loops on the
inside of tight turns cut out), the buoys and their passing sides, ramps, rocks and the
islands, and circles in magenta every wall point over water shallower than 2.5 m with the
coastline variation at its largest: the walls, not the seabed, must stop a craft.

--reverse, --mirror or both lay out another version of the course from the same spec, with its
own id (<id>_reverse, <id>_mirror, <id>_reverse_mirror), name, scene, menu map and CourseInfo;
the other options then apply to that version:

    python3 tools/courses/course_tool.py tools/courses/gull_cove.json --reverse --scene --thumb

Reversed, the control points run the other way from the same start line, and each offset s
along the course becomes length - s. Mirrored, x is negated in the control points, the start,
rocks, islands, props and the sun, and props turn the other way. Either one alone flips every
lateral offset and swaps red and yellow buoys, because the side the racer keeps each buoy on
flips; both together leave them as they are. Ramps face along the course, so they turn round
with it, and a ramp's landing ends up where its approach used to be: race each version before
shipping it. A spec's "versions" entry ({"reverse": {"order": 101, "conditions": "..."}})
overrides any of a version's keys.

--scene writes the course scene named in the spec and, next to it, the CourseInfo the menus
list (<id>.course.tres: menu order, id, name, conditions line, scene and menu map). Both are overwritten:
changes made to them in the editor are lost.
Needs numpy and Pillow.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

DEFAULT_SUN = {"rotation": [-50, 205, 0], "color": [1, 0.96, 0.88], "energy": 1.25}


def catmull_rom_closed(cps, step=1.0):
    P = [np.array(c[:2], float) for c in cps]
    W = [c[2] for c in cps]
    n = len(P)
    fine, widths = [], []
    for i in range(n):
        p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]
        t1 = math.sqrt(np.linalg.norm(p1 - p0))
        t2 = t1 + math.sqrt(np.linalg.norm(p2 - p1))
        t3 = t2 + math.sqrt(np.linalg.norm(p3 - p2))
        pieces = max(int(np.linalg.norm(p2 - p1) / 0.25), 4)
        for k in range(pieces):
            t = t1 + (t2 - t1) * k / pieces
            a1 = p0 * ((t1 - t) / t1) + p1 * (t / t1)
            a2 = p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
            a3 = p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
            b1 = a1 * ((t2 - t) / t2) + a2 * (t / t2)
            b2 = a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
            fine.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
            widths.append(W[i] + (W[(i + 1) % n] - W[i]) * k / pieces)
    fine = np.array(fine)
    widths = np.array(widths)
    closed = np.vstack([fine, fine[:1]])
    seg = np.linalg.norm(np.diff(closed, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seg)])
    length = cum[-1]
    count = max(int(length / step), 8)
    s = np.arange(count) * (length / count)
    wc = np.concatenate([widths, widths[:1]])
    pts = np.stack([np.interp(s, cum, closed[:, 0]), np.interp(s, cum, closed[:, 1])], 1)
    return pts, np.interp(s, cum, wc), length


class Course:
    def __init__(self, spec):
        self.spec = spec
        pts, ws, self.length = catmull_rom_closed(spec["control_points"])
        start = np.array(spec.get("start", spec["control_points"][0][:2]), float)
        s0 = int(np.argmin(np.linalg.norm(pts - start, axis=1)))
        self.pts = np.roll(pts, -s0, 0)
        self.ws = np.roll(ws, -s0)
        n = len(self.pts)
        self.step = self.length / n
        t = np.roll(self.pts, -1, 0) - np.roll(self.pts, 1, 0)
        self.tang = t / np.linalg.norm(t, axis=1)[:, None]
        self.right = np.stack([-self.tang[:, 1], self.tang[:, 0]], 1)

    def at(self, s, lateral=0.0):
        i = int(round(s / self.step)) % len(self.pts)
        return self.pts[i] + self.right[i] * lateral, self.tang[i]

    def walls(self):
        out = []
        for side in (-1, 1):
            line = [self.pts[i] + self.right[i] * side * self.ws[i] for i in range(len(self.pts))]
            out.append(remove_loops(line))
        return out


def seg_intersect(a, b, c, d):
    r, s = b - a, d - c
    den = r[0] * s[1] - r[1] * s[0]
    if abs(den) < 1e-12:
        return None
    t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
    return a + r * t if 0 <= t <= 1 and 0 <= u <= 1 else None


def remove_loops(line, window=160):
    n = len(line)
    out = []
    i = 0
    while i < n:
        out.append(line[i])
        a, b = line[i], line[(i + 1) % n]
        nxt = i + 1
        for k in range(2, window):
            j = i + k
            if j + 1 >= n:
                break
            x = seg_intersect(a, b, line[j], line[j + 1])
            if x is not None:
                out.append(x)
                nxt = j + 1
                break
        i = nxt
    return out


def terrain_height(spec, x, z, ragged=1.0):
    h = -16.0
    for cx, cz, r, peak in spec["islands"]:
        d = math.hypot(x - cx, z - cz) / (r * ragged)
        if d >= 1:
            continue
        t = 1 - d
        h = max(h, -16 + (peak + 16) * t * t * (3 - 2 * t))
    return h


def draw_map(course, path, scale=3.0):
    spec = course.spec
    walls = course.walls()
    allp = np.vstack([course.pts] + [np.array(w) for w in walls])
    minx, minz = allp.min(0) - 60
    maxx, maxz = allp.max(0) + 60
    W, H = int((maxx - minx) * scale), int((maxz - minz) * scale)
    img = Image.new("RGB", (W, H), (30, 80, 140))
    d = ImageDraw.Draw(img)
    P = lambda p: ((p[0] - minx) * scale, (p[1] - minz) * scale)
    for py in range(0, H, 3):
        for px in range(0, W, 3):
            h = terrain_height(spec, px / scale + minx, py / scale + minz)
            if h > 0:
                d.rectangle([px, py, px + 2, py + 2], fill=(220, 200, 130))
            elif h > -2:
                d.rectangle([px, py, px + 2, py + 2], fill=(80, 170, 180))
            elif h > -5:
                d.rectangle([px, py, px + 2, py + 2], fill=(50, 120, 170))
    rocks = [list(r) for r in spec.get("rocks", [])]
    for s, lat, r, hs in spec.get("course_rocks", []):
        p, _ = course.at(s, lat)
        rocks.append([p[0], p[1], r, hs])
    for x, z, r, hs in rocks:
        c = P((x, z))
        d.ellipse([c[0] - r * scale, c[1] - r * scale, c[0] + r * scale, c[1] + r * scale], fill=(130, 120, 110))
    for prop in spec.get("props", []):
        x, z = prop.get("at", (0, 0))
        if prop["type"] == "pier":
            yaw = math.radians(prop.get("yaw", 0))
            fwd = np.array([-math.sin(yaw), -math.cos(yaw)])
            side = np.array([fwd[1], -fwd[0]]) * prop.get("width", 4) / 2
            a0 = np.array([x, z])
            a1 = a0 + fwd * prop.get("length", 30)
            d.polygon([P(a0 - side), P(a1 - side), P(a1 + side), P(a0 + side)], fill=(150, 100, 60))
        elif prop["type"] == "building":
            c = P((x, z))
            d.rectangle([c[0] - 8, c[1] - 8, c[0] + 8, c[1] + 8], fill=(200, 190, 170))
        elif prop["type"] == "lamp":
            c = P((x, z))
            d.ellipse([c[0] - 3, c[1] - 3, c[0] + 3, c[1] + 3], fill=(255, 230, 120))
    for w in walls:
        d.line([P(p) for p in w] + [P(w[0])], fill=(255, 255, 255), width=2)
    d.line([P(p) for p in course.pts] + [P(course.pts[0])], fill=(110, 160, 220), width=1)
    bad = 0
    margin = spec.get("wall_depth", 2.5)
    for w in walls:
        for p in w[::2]:
            near_rock = min((math.hypot(p[0] - x, p[1] - z) - r * 1.3 for x, z, r, _ in rocks), default=99)
            if terrain_height(spec, p[0], p[1], 1.0 + spec["terrain"].get("coast_noise", 0.3)) > -margin or near_rock < 0:
                bad += 1
                c = P(p)
                d.ellipse([c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4], outline=(255, 0, 255), width=2)
    for k in range(0, int(course.length), 50):
        d.text(P(course.at(k)[0]), str(k), fill=(255, 255, 255))
    a, _ = course.at(0, -course.ws[0])
    b, _ = course.at(0, course.ws[0])
    d.line([P(a), P(b)], fill=(255, 255, 255), width=4)
    for kind, s, lat in spec["buoys"]:
        p, t = course.at(s, lat)
        side = -1 if kind == "red" else 1
        i = int(round(s / course.step)) % len(course.pts)
        q = p + course.right[i] * side * 4.0
        d.line([P(p), P(q)], fill=(255, 255, 255), width=1)
        col = (230, 40, 40) if kind == "red" else (250, 220, 30)
        c = P(p)
        d.ellipse([c[0] - 5, c[1] - 5, c[0] + 5, c[1] + 5], fill=col)
    for s, lat in spec.get("ramps", []):
        p, t = course.at(s, lat)
        r = np.array([-t[1], t[0]])
        poly = [p - t * 6 - r * 3.5, p + t * 6 - r * 3.5, p + t * 6 + r * 3.5, p - t * 6 + r * 3.5]
        d.polygon([P(q) for q in poly], fill=(240, 120, 30))
    img.save(path)
    return bad


def draw_thumb(course, path, size=420):
    """A small map for the menus: the corridor, the start line, buoys and ramps, on a clear background."""
    spec = course.spec
    walls = course.walls()
    allp = np.vstack([np.array(w) for w in walls])
    lo = allp.min(0) - 12
    hi = allp.max(0) + 12
    scale = (size - 8) / max(hi - lo)
    off = (np.array([size, size]) - (hi - lo) * scale) / 2
    ss = 3  # supersample, then shrink for smooth lines
    img = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    P = lambda p: tuple(((np.array(p[:2]) - lo) * scale + off) * ss)
    area = lambda w: abs(sum(w[i][0] * w[i - 1][1] - w[i - 1][0] * w[i][1] for i in range(len(w)))) / 2
    outer, inner = sorted(walls, key=area, reverse=True)
    d.polygon([P(p) for p in outer], fill=(20, 60, 130, 235))
    d.polygon([P(p) for p in inner], fill=(0, 0, 0, 0))
    d.line([P(p) for p in outer] + [P(outer[0])], fill=(255, 255, 255, 255), width=3 * ss)
    d.line([P(p) for p in inner] + [P(inner[0])], fill=(255, 255, 255, 255), width=3 * ss)
    a, _ = course.at(0, -course.ws[0])
    b, _ = course.at(0, course.ws[0])
    d.line([P(a), P(b)], fill=(255, 220, 30, 255), width=5 * ss)
    for kind, s, lat in spec["buoys"]:
        p, _ = course.at(s, lat)
        c = P(p)
        col = (235, 50, 40, 255) if kind == "red" else (255, 215, 30, 255)
        r = 4 * ss
        d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=col)
    for s, lat in spec.get("ramps", []):
        p, t = course.at(s, lat)
        c = P(p)
        r = 5 * ss
        d.rectangle([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=(250, 130, 30, 255))
    img = img.resize((size, size), Image.LANCZOS)
    img.save(path)


def transform(pos, fwd, y=0.0):
    fx, fz = fwd
    # Basis columns: x = right of travel (-fz, 0, fx), y = up, z = backward (-fx, 0, -fz).
    # Scene files list the basis by rows.
    xx, xz = -fz, fx
    zx, zz = -fx, -fz
    return "Transform3D(%.5f, 0, %.5f, 0, 1, 0, %.5f, 0, %.5f, %.3f, %.3f, %.3f)" % (xx, zx, xz, zz, pos[0], y, pos[1])


def write_scene(course, path):
    spec = course.spec
    out = ['[gd_scene format=3]', '']
    for t, p, i in [
        ('Script', 'res://course/course.gd', 'course'),
        ('Environment', spec.get("environment", 'res://environment/day_environment.tres'), 'env'),
        ('Script', 'res://environment/sun.gd', 'sun'),
        ('Script', 'res://water/ocean_surface.gd', 'ocean'),
        ('Resource', spec["waves"], 'waves'),
        ('Material', 'res://water/ocean_material.tres', 'water_mat'),
        ('Script', 'res://water/shore_map.gd', 'shore'),
        ('Script', 'res://environment/terrain.gd', 'terrain'),
        ('Script', 'res://environment/rock.gd', 'rock'),
        ('PackedScene', 'res://course/buoy.tscn', 'buoy'),
        ('PackedScene', 'res://course/ramp.tscn', 'ramp'),
        ('PackedScene', 'res://course/start_gate.tscn', 'gate'),
        ('Script', 'res://environment/pier.gd', 'pier'),
        ('Script', 'res://environment/lamp_post.gd', 'lamp'),
        ('Script', 'res://environment/harbor_building.gd', 'building'),
    ]:
        if i in ("pier", "lamp", "building") and not any(prop["type"] == i for prop in spec.get("props", [])):
            continue
        out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, i))
    out.append('')
    cps = spec["control_points"]
    out += ['[node name="%s" type="Node3D"]' % spec["root"],
            'script = ExtResource("course")',
            'course_name = "%s"' % spec["name"],
            'laps = %d' % spec.get("laps", 3),
            'grid_distance = %g' % spec.get("grid_distance", 12),
            ] + (['lap_levels = PackedFloat32Array(%s)' % ", ".join("%g" % v for v in spec["lap_levels"])]
                 if spec.get("lap_levels") else []) + [
            'control_points = PackedVector3Array(%s)' % ", ".join("%g, 0, %g" % (c[0], c[1]) for c in cps),
            'half_widths = PackedFloat32Array(%s)' % ", ".join("%g" % c[2] for c in cps), '']
    sun = spec.get("sun", DEFAULT_SUN)
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]', 'environment = ExtResource("env")', '',
            '[node name="Sun" type="DirectionalLight3D" parent="."]',
            'rotation_degrees = Vector3(%g, %g, %g)' % tuple(sun["rotation"]),
            'light_color = Color(%g, %g, %g, 1)' % tuple(sun["color"]),
            'light_energy = %g' % sun["energy"],
            'shadow_enabled = true', 'directional_shadow_max_distance = 220.0', 'script = ExtResource("sun")', '',
            '[node name="OceanSurface" type="MeshInstance3D" parent="."]', 'script = ExtResource("ocean")',
            'wave_set = ExtResource("waves")', 'water_material = ExtResource("water_mat")']
    if spec.get("water"):
        items = []
        for key, value in spec["water"].items():
            if isinstance(value, list):
                value = "Color(%g, %g, %g, 1)" % tuple(value[:3])
            items.append('"%s": %s' % (key, value))
        out.append('shader_overrides = {%s}' % ", ".join(items))
    out += ['',
            '[node name="ShoreMap" type="Node3D" parent="."]', 'script = ExtResource("shore")', '']
    ter = spec["terrain"]
    out += ['[node name="Terrain" type="MeshInstance3D" parent="."]', 'script = ExtResource("terrain")',
            'size = %g' % ter.get("size", 700), 'cells = %d' % ter.get("cells", 175),
            'islands = Array[Vector4]([%s])' % ", ".join("Vector4(%g, %g, %g, %g)" % tuple(i) for i in spec["islands"]),
            'coast_noise = %g' % ter.get("coast_noise", 0.3), '']
    sp, st = course.at(0)
    out += ['[node name="StartLine" type="Marker3D" parent="."]', 'transform = ' + transform(sp, st), '',
            '[node name="StartGate" parent="." instance=ExtResource("gate")]', 'transform = ' + transform(sp, st),
            'span = %g' % spec.get("gate_span", 2 * course.ws[0] + 2),
            'height = %g' % spec.get("gate_height", 11), '',
            '[node name="Buoys" type="Node3D" parent="."]', '']
    for k, (kind, s, lat) in enumerate(spec["buoys"]):
        p, _ = course.at(s, lat)
        out += ['[node name="Buoy%02d" parent="Buoys" instance=ExtResource("buoy")]' % (k + 1),
                'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.3f, 0, %.3f)' % (p[0], p[1])]
        if kind == "yellow":
            out.append('kind = 1')
        if spec.get("lit_buoys"):
            out.append('lamp_energy = %g' % spec.get("buoy_lamp_energy", 2.5))
        out.append('')
    out += ['[node name="Ramps" type="Node3D" parent="."]', '']
    for k, (s, lat) in enumerate(spec.get("ramps", [])):
        p, t = course.at(s, lat)
        out += ['[node name="Ramp%d" parent="Ramps" instance=ExtResource("ramp")]' % (k + 1), 'transform = ' + transform(p, t)]
        if "ramp_bottom" in spec:
            # Deeper foot, same 17.6 degree slope (the default ramp rises 3.8 m over 12 m).
            out += ['bottom = %g' % spec["ramp_bottom"], 'length = %.2f' % (12.0 * (1.8 - spec["ramp_bottom"]) / 3.8)]
        out.append('')
    out += ['[node name="Rocks" type="Node3D" parent="."]', '']
    rocks = []
    for s, lat, r, hs in spec.get("course_rocks", []):
        p, _ = course.at(s, lat)
        rocks.append([p[0], p[1], r, hs])
    rocks += [list(r) for r in spec.get("rocks", [])]
    seeds = [3, 11, 5, 17, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61]
    for k, (x, z, r, hs) in enumerate(rocks):
        out += ['[node name="Rock%d" type="StaticBody3D" parent="Rocks"]' % (k + 1),
                'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.2f, -1.5, %.2f)' % (x, z),
                'script = ExtResource("rock")', 'radius = %g' % r, 'height_scale = %g' % hs,
                'rock_seed = %d' % seeds[(k + 1) % len(seeds)], '']
    out += write_props(spec, course)
    with open(path, "w") as f:
        f.write("\n".join(out))


VERSIONS = {
    # key: (name suffix, conditions prefix, order added to the course's)
    "reverse": ("Reverse", "Reversed", 100),
    "mirror": ("Mirror", "Mirrored", 200),
    "reverse_mirror": ("Reverse Mirror", "Reversed and mirrored", 300),
}


def version_spec(spec, reverse=False, mirror=False):
    """The spec of the course run the other way (reverse), mirrored left to right (mirror), or both."""
    if not reverse and not mirror:
        return spec
    key = "_".join(k for k, on in (("reverse", reverse), ("mirror", mirror)) if on)
    length = Course(spec).length
    out = json.loads(json.dumps(spec))
    out.pop("versions", None)
    sx = -1 if mirror else 1
    # Lateral offsets and buoy colours flip when exactly one of the two applies.
    flip = -1 if reverse != mirror else 1

    def offset(s):
        return round((length - s) % length, 1) if reverse else s

    def along(item):
        """An [offset, lateral, ...] entry."""
        return [offset(item[0]), item[1] * flip] + list(item[2:])

    start = spec.get("start", spec["control_points"][0][:2])
    out["start"] = [start[0] * sx, start[1]]
    cps = [[c[0] * sx, c[1], c[2]] for c in spec["control_points"]]
    out["control_points"] = cps[::-1] if reverse else cps
    swap = {"red": "yellow", "yellow": "red"}
    buoys = [[swap[k] if flip < 0 else k, offset(s), lat * flip] for k, s, lat in spec["buoys"]]
    out["buoys"] = sorted(buoys, key=lambda b: b[1])
    out["ramps"] = sorted((along(r) for r in spec.get("ramps", [])), key=lambda r: r[0])
    out["course_rocks"] = [along(r) for r in spec.get("course_rocks", [])]
    out["rocks"] = [[r[0] * sx] + list(r[1:]) for r in spec.get("rocks", [])]
    out["islands"] = [[i[0] * sx] + list(i[1:]) for i in spec["islands"]]
    props = []
    for prop in spec.get("props", []):
        prop = dict(prop)
        if "offset" in prop:
            prop["offset"] = along(prop["offset"])
        if "at" in prop:
            prop["at"] = [prop["at"][0] * sx, prop["at"][1]]
        if mirror and "yaw" in prop:
            prop["yaw"] = -prop["yaw"]
        props.append(prop)
    if props:
        out["props"] = props
    if mirror:
        sun = dict(spec.get("sun", DEFAULT_SUN))
        sun["rotation"] = [sun["rotation"][0], -sun["rotation"][1], -sun["rotation"][2]]
        out["sun"] = sun
    suffix, prefix, order = VERSIONS[key]
    out["id"] = "%s_%s" % (spec["id"], key)
    out["name"] = "%s %s" % (spec["name"], suffix)
    out["root"] = spec["root"] + suffix.replace(" ", "")
    out["scene"] = os.path.join(os.path.dirname(spec["scene"]), out["id"] + ".tscn")
    out["order"] = spec.get("order", 0) + order
    out["conditions"] = "%s. %s" % (prefix, spec["conditions"])
    out.update(spec.get("versions", {}).get(key, {}))
    return out


def godot_string(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def info_path(spec, project):
    """Where the CourseInfo goes: <id>.course.tres next to the course scene."""
    return os.path.join(project, os.path.dirname(spec["scene"]), spec["id"] + ".course.tres")


def thumb_path(spec, project):
    return os.path.join(project, spec["scene"].replace(".tscn", "_map.png"))


def write_info(spec, path):
    """The CourseInfo resource the menus list: menu order, id, name, conditions, scene and menu map."""
    out = ['[gd_resource type="Resource" script_class="CourseInfo" load_steps=3 format=3]', '',
           '[ext_resource type="Script" path="res://course/course_info.gd" id="1"]',
           '[ext_resource type="Texture2D" path="res://%s" id="2"]' % thumb_path(spec, "").lstrip("/"), '',
           '[resource]',
           'script = ExtResource("1")',
           'order = %d' % spec.get("order", 0),
           'id = %s' % godot_string(spec["id"]),
           'display_name = %s' % godot_string(spec["name"]),
           'conditions = %s' % godot_string(spec["conditions"]),
           'scene = %s' % godot_string("res://" + spec["scene"]),
           'map = ExtResource("2")', '']
    with open(path, "w") as f:
        f.write("\n".join(out))


def write_props(spec, course):
    """Piers, lamps and buildings: {"type", "at": [x, z] or "offset": [s, lateral], "yaw" (degrees), ...}."""
    if not spec.get("props"):
        return []
    out = ['[node name="Props" type="Node3D" parent="."]', '']
    for k, prop in enumerate(spec.get("props", [])):
        if "offset" in prop:
            p, _ = course.at(*prop["offset"])
            x, z = p
        else:
            x, z = prop["at"]
        yaw = math.radians(prop.get("yaw", 0))
        c, s = math.cos(yaw), math.sin(yaw)
        y = prop.get("y", 0)
        xf = "Transform3D(%.5f, 0, %.5f, 0, 1, 0, %.5f, 0, %.5f, %.3f, %.3f, %.3f)" % (c, s, -s, c, x, y, z)
        kind = prop["type"]
        out += ['[node name="%s%d" type="%s" parent="Props"]' % (kind.capitalize(), k + 1,
                {"pier": "StaticBody3D", "lamp": "Node3D", "building": "Node3D"}[kind]),
                'transform = ' + xf, 'script = ExtResource("%s")' % kind]
        for key, value in prop.items():
            if key in ("type", "at", "offset", "yaw", "y"):
                continue
            if isinstance(value, list) and len(value) == 3 and key == "size":
                out.append('%s = Vector3(%g, %g, %g)' % (key, *value))
            elif isinstance(value, list):
                out.append('%s = Color(%g, %g, %g, 1)' % (key, *value[:3]))
            else:
                out.append('%s = %s' % (key, value))
        out.append('')
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("--map", help="write a top-down map PNG here")
    ap.add_argument("--scene", action="store_true",
                    help="write the course scene named in the spec and its CourseInfo (<id>.course.tres)")
    ap.add_argument("--thumb", action="store_true", help="write the menu map next to the course scene (<scene>_map.png)")
    ap.add_argument("--reverse", action="store_true", help="lay out the course run the other way (<id>_reverse)")
    ap.add_argument("--mirror", action="store_true", help="lay out the course mirrored left to right (<id>_mirror)")
    ap.add_argument("--project", default=os.path.join(os.path.dirname(__file__), "..", ".."))
    args = ap.parse_args()
    spec = version_spec(json.load(open(args.spec)), args.reverse, args.mirror)
    course = Course(spec)
    print("%s: %.1f m a lap, %d buoys" % (spec["name"], course.length, len(spec["buoys"])))
    if args.map:
        bad = draw_map(course, args.map)
        print("map: %s; wall points over shallow water: %d" % (args.map, bad))
    if args.thumb:
        path = thumb_path(spec, args.project)
        draw_thumb(course, path)
        print("thumb:", os.path.normpath(path))
    if args.scene:
        path = os.path.join(args.project, spec["scene"])
        write_scene(course, path)
        print("scene:", os.path.normpath(path))
        path = info_path(spec, args.project)
        write_info(spec, path)
        print("course info:", os.path.normpath(path))


if __name__ == "__main__":
    main()
