# Waterline

A jet ski racer in Godot 4.7 (Forward+, typed GDScript, Jolt physics), a spiritual successor to a
1996 jet ski racer. All names, art, sound and courses are original.

Race four riders on four craft over seven courses, in a championship, a quick race, a time trial
against your best run's ghost, or stunt mode. The weather can change during a race.

## Running it

Open `godot/project.godot` in Godot 4.7 and press F5, or:

```sh
godot --path godot
```

The game opens on the main menu. The race scene also runs on its own, with arguments after `--`:

```sh
godot --path godot --scene res://race/race.tscn -- --rider koa --course whitecap_point --weather storm
```

`--rider`, `--craft`, `--course`, `--mode` (`quick_race`, `championship`, `time_trial`, `stunt`),
`--laps`, `--weather` (with `--weather-lap` and `--weather-time` for a change), `--no-opponents`
and `--watch` (the computer rides every craft). `res://levels/open_water.tscn` is a free ride on open
water (`-- --demo` rides itself).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Throttle | Space, J | A, right trigger |
| Steer | A / D, Left / Right | left stick, D-pad |
| Lean forward / back | W / S, Up / Down | left stick up / down, D-pad |
| Stunt (in the air; the direction held picks it) | K, Left Shift | B, X |
| Back on the course | R | Back |
| Pause | Escape, P | Start |
| Camera | C | Y |
| Next rider (watch mode) | Tab | right shoulder |
| Debug readout | F3 | |

Every action can be rebound in Options. The free camera (water test scene) uses W A S D, E / Q,
Shift, the right mouse button to look and the wheel for speed.

## Layout

| Folder | What's in it |
|---|---|
| `godot/` | the game: the Godot project, its scenes, scripts, assets and tests (`res://` is here) |
| `tools/` | the course tool and the course specs it builds into `godot/levels/` |
| `docs/` | screenshots |
| `build/` | exports (not in git) |

## Working on it

- The [wiki](https://github.com/astrosteveo/waterline/wiki) explains how each part of the game
  works and why: the water, the jet ski, courses, races, computer riders, weather, testing.
- [Issues](https://github.com/astrosteveo/waterline/issues) hold what's planned and what's broken.
- CI checks that every script, scene and resource loads. The gameplay scenarios in
  `godot/test/scenarios/` need a GPU and run locally with [gdh](https://github.com/astrosteveo/gdh):
  `gdh test --project godot`. See the wiki's [Testing](https://github.com/astrosteveo/waterline/wiki/Testing) page.
