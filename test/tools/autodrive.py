"""Rides the player's craft round a course through gdh, with real input.

Every few frames it reads the craft's state from the running game, picks a point ahead on
the course (through each buoy's passing side), and steers toward it with the gamepad
stick (left_x) while holding the throttle, as a player would. It is a test tool: the
computer riders in the game have their own driver.

    uv run --project ~/Projects/gdh python test/tools/autodrive.py --laps 1
"""
import argparse
import json
import math
import sys

from gdh.client import Session

ap = argparse.ArgumentParser()
ap.add_argument("--project", default=".")
ap.add_argument("--scene", default="res://race/race.tscn")
ap.add_argument("--session", default="autodrive")
ap.add_argument("--laps", type=int, default=1)
ap.add_argument("--every", type=int, default=3, help="frames between steering updates")
ap.add_argument("--clearance", type=float, default=4.5, help="meters to pass beside a buoy")
ap.add_argument("--wrong-side", type=int, default=-1, help="pass this buoy index on the wrong side")
ap.add_argument("--max-seconds", type=float, default=400)
ap.add_argument("--keyboard", action="store_true", help="steer with the digital steer actions")
ap.add_argument("--attach", action="store_true", help="drive an already running session")
ap.add_argument("--out", default="")
ap.add_argument("--start-offset", type=float, default=None, help="respawn here (meters along the course)")
ap.add_argument("--start-lateral", type=float, default=0.0)
ap.add_argument("--start-speed", type=float, default=0.0)
ap.add_argument("--lateral", type=float, default=None, help="hold this lateral offset instead of the buoy line")
ap.add_argument("--seconds", type=float, default=None, help="stop after this many seconds")
ap.add_argument("--shots", default="", help="comma-separated course offsets to take a screenshot at")
ap.add_argument("--shot-dir", default="captures/autodrive")
args = ap.parse_args()

R = "scene"  # the race node is the scene root


def main(game):
    info = game.eval(f"[{R}.course.length, {R}.laps, {R}.course.gate_table()]")
    length, laps, gates = info[0], info[1], info[2]
    keys = []  # (offset, lateral) the line passes through
    for i, (off, side, lat) in enumerate(gates):
        s = side if i != args.wrong_side else -side
        keys.append((off, lat + s * args.clearance))
    keys.sort()

    def lateral_at(s):
        s %= length
        if not keys:
            return 0.0
        # Hold each buoy's passing point from 25 m before to 10 m after; ease between.
        best = None
        for off, lat in keys:
            d = (s - off + length / 2) % length - length / 2
            if -25 <= d <= 10:
                return lat
        prev = max([k for k in keys if k[0] <= s], default=keys[-1])
        nxt = min([k for k in keys if k[0] > s], default=keys[0])
        a = (prev[0] + 10) % length
        b = (nxt[0] - 25) % length
        span = (b - a) % length
        t = ((s - a) % length) / span if span > 1 else 1
        t = min(max(t, 0), 1)
        t = t * t * (3 - 2 * t)
        return prev[1] * (1 - t) + nxt[1] * t

    if args.start_offset is not None:
        game.eval(f"{R}.player.craft.respawn({R}.course.transform_at({args.start_offset}, {args.start_lateral}))")
        game.eval(f"{R}.player.set('teleport_ticks', 2)")
        game.step(2)
        if args.start_speed > 0:
            game.eval(f"{R}.player.craft.set('linear_velocity', {R}.course.tangent_at({args.start_offset}) * {args.start_speed})")
    if args.lateral is not None:
        fixed = args.lateral
        lateral_at = lambda s: fixed
    shots = sorted(float(x) for x in args.shots.split(",") if x)
    frames = 0
    log = []
    hold = ["throttle"]
    while frames < args.max_seconds * 60:
        st = game.eval(
            f"[{R}.player.craft.global_position, -{R}.player.craft.global_basis.z, {R}.player.craft.speed, "
            f"{R}.player.progress.offset, {R}.player.progress.distance, {R}.player.laps_done, "
            f"{R}.race_time, {R}.phase, {R}.player.buoys_passed, {R}.player.buoys_missed]")
        pos, nose, speed, offset, distance, laps_done, race_time, phase, passed, missed = st
        if laps_done >= args.laps or phase == 2:
            break
        if args.seconds is not None and frames >= args.seconds * 60:
            break
        while shots and (offset - shots[0]) % length < 50 and (offset - shots[0]) % length >= 0:
            game.shot(out=f"{args.shot_dir}/s{int(shots[0]):04d}.png", max_width=1280)
            shots.pop(0)
        look = 7.0 + speed * 0.55
        s_target = offset + look
        lat = lateral_at(s_target)
        target = game.eval(f"{R}.course.transform_at({s_target}, {lat}).origin")
        dx, dz = target[0] - pos[0], target[2] - pos[2]
        want = math.atan2(-dx, -dz)
        have = math.atan2(-nose[0], -nose[2])
        err = (want - have + math.pi) % (2 * math.pi) - math.pi
        steer = max(-1.0, min(1.0, -err * 2.2))
        lean = 0.0
        inputs = {"hold": hold}
        if abs(err) > 0.45 and speed > 8:
            inputs["hold"] = hold + ["lean_forward"]
        if args.keyboard:
            if steer > 0.3:
                inputs["hold"] = inputs["hold"] + ["steer_right"]
            elif steer < -0.3:
                inputs["hold"] = inputs["hold"] + ["steer_left"]
        else:
            inputs["axis"] = f"left_x={steer:.3f}"
        game.step(args.every, **inputs)
        frames += args.every
        extra = game.eval(f"[{R}.player.craft.airborne, {R}.player.craft.clearance, {R}.player.craft.telemetry().pitch_degrees, {R}.player.progress.lateral]")
        log.append({"air": extra[0], "clearance": extra[1], "pitch": extra[2], "lateral": extra[3], "t": race_time, "pos": pos, "speed": speed, "offset": offset,
                    "distance": distance, "laps": laps_done, "passed": passed, "missed": missed})
    result = game.eval(
        f"{{'laps_done': {R}.player.laps_done, 'lap_times': {R}.player.lap_times, "
        f"'passed': {R}.player.buoys_passed, 'missed': {R}.player.buoys_missed, "
        f"'race_time': {R}.race_time, 'phase': {R}.phase, 'distance': {R}.player.progress.distance, "
        f"'power': {R}.player.power, 'crashes': {R}.player.crashes, 'place': {R}.player.place}}")
    print(json.dumps(result))
    if args.out:
        with open(args.out, "w") as f:
            json.dump({"result": result, "log": log}, f)


if args.attach:
    with Session.attach(args.session) as game:
        main(game)
else:
    with Session.start(args.project, scene=args.scene, name=args.session, seed=1) as game:
        game.step(200)
        main(game)
