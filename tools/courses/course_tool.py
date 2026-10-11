"""Lays out a course from a JSON spec: draws a top-down map and writes the course scene.

    python3 tools/courses/course_tool.py tools/courses/gull_cove.json --map captures/gull_cove_map.png
    python3 tools/courses/course_tool.py tools/courses/gull_cove.json --scene   # writes the .tscn

The spec gives the centre line's control points [x, z, half width] (clockwise or not, in
order of travel), buoys, ramps and rocks by [offset along the course from the start line,
meters right of the centre line, ...], and terrain islands [x, z, radius, peak height]. The
centre line is the same centripetal Catmull-Rom curve the game builds (course/course.gd), so
offsets here match offsets in the game. The map shows the walls (with the loops on the
inside of tight turns cut out), the buoys and their passing sides, ramps, rocks and the
islands, and circles in magenta every wall point over water shallower than 2.5 m with the
coastline variation at its largest: the walls, not the seabed, must stop a craft.

Writing the scene overwrites it: changes made to it in the editor are lost.
Needs numpy and Pillow.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw


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
    ]:
        out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, i))
    out.append('')
    cps = spec["control_points"]
    out += ['[node name="%s" type="Node3D"]' % spec["root"],
            'script = ExtResource("course")',
            'course_name = "%s"' % spec["name"],
            'laps = %d' % spec.get("laps", 3),
            'grid_distance = %g' % spec.get("grid_distance", 12),
            'control_points = PackedVector3Array(%s)' % ", ".join("%g, 0, %g" % (c[0], c[1]) for c in cps),
            'half_widths = PackedFloat32Array(%s)' % ", ".join("%g" % c[2] for c in cps), '']
    sun = spec.get("sun", {"rotation": [-50, 205, 0], "color": [1, 0.96, 0.88], "energy": 1.25})
    out += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]', 'environment = ExtResource("env")', '',
            '[node name="Sun" type="DirectionalLight3D" parent="."]',
            'rotation_degrees = Vector3(%g, %g, %g)' % tuple(sun["rotation"]),
            'light_color = Color(%g, %g, %g, 1)' % tuple(sun["color"]),
            'light_energy = %g' % sun["energy"],
            'shadow_enabled = true', 'directional_shadow_max_distance = 220.0', 'script = ExtResource("sun")', '',
            '[node name="OceanSurface" type="MeshInstance3D" parent="."]', 'script = ExtResource("ocean")',
            'wave_set = ExtResource("waves")', 'water_material = ExtResource("water_mat")', '',
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
        out.append('')
    out += ['[node name="Ramps" type="Node3D" parent="."]', '']
    for k, (s, lat) in enumerate(spec.get("ramps", [])):
        p, t = course.at(s, lat)
        out += ['[node name="Ramp%d" parent="Ramps" instance=ExtResource("ramp")]' % (k + 1), 'transform = ' + transform(p, t), '']
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
    with open(path, "w") as f:
        f.write("\n".join(out))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("--map", help="write a top-down map PNG here")
    ap.add_argument("--scene", action="store_true", help="write the course scene named in the spec")
    ap.add_argument("--project", default=os.path.join(os.path.dirname(__file__), "..", ".."))
    args = ap.parse_args()
    spec = json.load(open(args.spec))
    course = Course(spec)
    print("%s: %.1f m a lap, %d buoys" % (spec["name"], course.length, len(spec["buoys"])))
    if args.map:
        bad = draw_map(course, args.map)
        print("map: %s; wall points over shallow water: %d" % (args.map, bad))
    if args.scene:
        path = os.path.join(args.project, spec["scene"])
        write_scene(course, path)
        print("scene:", os.path.normpath(path))


if __name__ == "__main__":
    main()
