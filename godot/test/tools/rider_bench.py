"""Measures how each rider rides their default craft (or --craft) on open water: 0 to
50 km/h, top speed, a full-lock U-turn at speed and the slip in it.

    uv run --project ~/Projects/gdh python godot/test/tools/rider_bench.py [--riders marina,koa]
"""
import argparse
import os
import math

from gdh.client import Session

ap = argparse.ArgumentParser()
ap.add_argument("--project", default=os.path.join(os.path.dirname(__file__), "..", ".."))
ap.add_argument("--riders", default="marina,koa,ines,dax,marina")
ap.add_argument("--craft", default="", help="put every rider on this craft (an id) instead of their own")
ap.add_argument("--flat", action="store_true", help="flat water, to compare the stats alone")
ap.add_argument("--yaw", type=float, default=-1.134, help="heading: -1.134 rides with the swells")
args = ap.parse_args()

CRAFT = "scene.get_node('JetSki')"


def run(game, rider):
    # The rider's default craft, or --craft for everyone: the craft's stats, then the rider's weight.
    craft = f"Game.craft_named('{args.craft}')" if args.craft else f"Game.rider_named('{rider}').default_craft"
    game.eval(f"{CRAFT}.set('tuning', {craft}.tuning_for(Game.rider_named('{rider}')))")
    game.eval(f"{CRAFT}._apply_body_tuning()")
    game.eval(f"{CRAFT}.respawn(Transform3D(Basis(Vector3(0,1,0), {args.yaw}), Vector3(0,0,0)))")
    game.step(2)
    # The same waves for every rider.
    game.eval("Ocean.reset_time(5.0)")
    t50 = None
    t40 = None
    speeds = []
    for frame in range(900):
        game.step(1, hold="throttle")
        v = game.eval(f"{CRAFT}.speed") * 3.6
        speeds.append(v)
        if t40 is None and v >= 40:
            t40 = (frame + 1) / 60
        if t50 is None and v >= 50:
            t50 = (frame + 1) / 60
    top = sum(speeds[-180:]) / 180
    # U-turn at full lock from top speed.
    start = game.eval(f"atan2({CRAFT}.global_basis.z.x, {CRAFT}.global_basis.z.z)")
    turned = 0.0
    last = start
    slip = 0.0
    t180 = None
    for frame in range(400):
        game.step(1, hold=["throttle", "steer_right"])
        h, s = game.eval(f"[atan2({CRAFT}.global_basis.z.x, {CRAFT}.global_basis.z.z), {CRAFT}.slip_angle]")
        d = (h - last + math.pi) % (2 * math.pi) - math.pi
        turned += abs(d)
        last = h
        slip = max(slip, abs(math.degrees(s)))
        if turned >= math.pi:
            t180 = (frame + 1) / 60
            break
    end_speed = game.eval(f"{CRAFT}.speed") * 3.6
    print(f"{rider:8s} 0-40 {t40 or 0:4.2f} s  0-50 {t50 or 0:4.2f} s  top {top:5.1f} km/h  U-turn {t180 or 0:4.2f} s"
          f"  max slip {slip:4.1f} deg  speed after turn {end_speed:4.1f} km/h", flush=True)


with Session.start(args.project, scene="res://levels/open_water.tscn", seed=1, echo=False) as game:
    if args.flat:
        game.eval("Ocean.wave_set.set('amplitude_scale', 0.0)")
    for rider in args.riders.split(","):
        run(game, rider)
