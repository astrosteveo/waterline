@tool
class_name JetSkiTuning
extends Resource
## Every number that shapes how a jet ski rides. [JetSki] reads these each physics tick,
## so they can be changed while the game runs. NOTES.md records the chosen values and why.

@export_group("Body")
## Craft plus rider, in kilograms.
@export_range(50.0, 1000.0, 1.0, "suffix:kg") var mass: float = 300.0
## Centre of mass in the craft's local space (origin at the keel, mid-length; -Z is forward).
@export var center_of_mass: Vector3 = Vector3(0.0, 0.32, 0.12)
## Moments of inertia about the local X (pitch), Y (yaw) and Z (roll) axes, in kg m².
@export var inertia: Vector3 = Vector3(170.0, 190.0, 50.0)

@export_group("Buoyancy")
## Upward force per meter of depth at each hull point, in newtons. With 8 points and 300 kg,
## 3100 floats the hull about 12 cm deep at rest.
@export_range(0.0, 20000.0, 1.0, "suffix:N/m") var buoyancy_stiffness: float = 3100.0
## Depth past which a hull point adds no more buoyancy (the deck is under water).
@export_range(0.05, 2.0, 0.01, "suffix:m") var max_point_depth: float = 0.45
## Force per m/s with which the water resists a submerged hull point moving through the
## surface, in either direction. Too little and landings bounce like a trampoline.
@export_range(0.0, 5000.0, 1.0, "suffix:N/(m/s)") var water_damping: float = 600.0
## Extra resistance to pressing in that grows with the square of the speed (slamming), per (m/s)².
@export_range(0.0, 2000.0, 1.0) var slam_damping: float = 45.0
## Share of [member water_damping] that resists a point rising out of the water. Below 1,
## so the craft can still leave the water off a crest.
@export_range(0.0, 1.0, 0.01) var release_share: float = 0.7
## Depth over which a hull point's water forces fade in, so entry is smooth.
@export_range(0.005, 0.5, 0.001, "suffix:m") var wet_depth: float = 0.06
## Direction of the buoyancy: 0 straight up, 1 along the wave's surface normal, so a slope
## pushes the craft downhill as a real wave face does.
@export_range(0.0, 1.0, 0.01) var normal_follow: float = 1.0
## Lift from planing, per (m/s)² of forward speed, while the hull is in the water.
@export_range(0.0, 50.0, 0.1) var planing_lift: float = 2.5

@export_group("Engine")
## Jet thrust at full throttle, in newtons.
@export_range(0.0, 20000.0, 1.0, "suffix:N") var max_thrust: float = 2400.0
## How quickly the thrust follows the throttle, per second.
@export_range(0.1, 50.0, 0.1) var throttle_response: float = 6.0
## Distance below the centre of mass the thrust acts at; under power it lifts the bow.
@export_range(-1.0, 1.0, 0.01, "suffix:m") var thrust_pitch_lever: float = 0.1
## Depth the intake (the rear hull points) needs for full thrust. Out of the water, no thrust.
@export_range(0.005, 0.5, 0.001, "suffix:m") var intake_depth: float = 0.05

@export_group("Drag")
## Water drag along the hull, per m/s of speed through the water.
@export_range(0.0, 1000.0, 0.1) var linear_drag: float = 30.0
## Water drag along the hull, per (m/s)² of speed. With the thrust it sets the top speed:
## 2400 N = 30 * v + 6.1 * v² gives about 17.5 m/s (63 km/h).
@export_range(0.0, 100.0, 0.01) var quadratic_drag: float = 6.1
## Drag multiplier when the hull is fully under water rather than skimming.
@export_range(1.0, 5.0, 0.01) var deep_drag_multiplier: float = 1.6
## Air drag, per (m/s)².
@export_range(0.0, 5.0, 0.01) var air_drag: float = 0.25

@export_group("Steering")
## Turn rate at full steer, at low speed, in radians per second.
@export_range(0.0, 6.0, 0.01, "suffix:rad/s") var turn_rate_low: float = 1.6
## Turn rate at full steer at top speed.
@export_range(0.0, 6.0, 0.01, "suffix:rad/s") var turn_rate_high: float = 1.15
## Speed at which the turn rate starts falling from turn_rate_low toward turn_rate_high.
@export_range(0.0, 40.0, 0.1, "suffix:m/s") var turn_rate_peak_speed: float = 8.0
## Speed counted as top speed for steering and camera effects.
@export_range(1.0, 60.0, 0.1, "suffix:m/s") var reference_top_speed: float = 17.5
## Share of the turn rate left with the throttle released (the jet steers the craft).
@export_range(0.0, 1.0, 0.01) var coast_steer: float = 0.55
## How quickly the yaw rate follows the steering, per second.
@export_range(0.1, 50.0, 0.1) var yaw_response: float = 9.0
## Largest yaw acceleration the steering can produce, in rad/s².
@export_range(0.1, 100.0, 0.1) var max_yaw_acceleration: float = 14.0
## Bank angle into a full-lock turn at speed, in degrees.
@export_range(0.0, 60.0, 0.1, "degrees") var bank_angle: float = 20.0
## Torque per radian of bank error, in N m.
@export_range(0.0, 10000.0, 1.0) var bank_stiffness: float = 9000.0

@export_group("Grip")
## How quickly the hull cancels sideways motion, per second.
@export_range(0.0, 50.0, 0.1) var grip_rate: float = 12.0
## Most sideways force the hull can make, in g. Past it the craft slides.
@export_range(0.0, 10.0, 0.01) var grip_g: float = 1.9
## Slip angle at which the steering stops turning the nose further from the direction of
## travel, so a slide doesn't become a spin.
@export_range(0.0, 90.0, 0.1, "degrees") var slip_limit: float = 28.0
## How strongly the slip limit pulls the nose back, per second per radian of excess.
@export_range(0.0, 50.0, 0.1) var slip_recovery: float = 6.0

@export_group("Lean")
## Pitch torque from a full lean while on the water, in N m.
@export_range(0.0, 10000.0, 1.0) var lean_torque: float = 900.0
## The lean stops pushing once the nose is this far below the water's surface plane...
@export_range(0.0, 45.0, 0.1, "degrees") var lean_forward_max_pitch: float = 10.0
## ...or this far above it. The bow-up trim at speed stops there too.
@export_range(0.0, 45.0, 0.1, "degrees") var lean_back_max_pitch: float = 15.0
## Torque per radian past those limits that pushes the nose back, so the craft can't
## stand on its tail or bury its nose while on the water.
@export_range(0.0, 50000.0, 1.0) var pitch_limit_stiffness: float = 8000.0
## Leaning forward digs the nose in: these multiply grip, turn rate and drag at full lean.
@export_range(0.0, 3.0, 0.01) var lean_forward_grip: float = 1.35
@export_range(0.0, 3.0, 0.01) var lean_forward_turn: float = 1.3
@export_range(0.0, 3.0, 0.01) var lean_forward_drag: float = 1.15
## Leaning back lifts the nose: less grip and turning, a little less drag.
@export_range(0.0, 3.0, 0.01) var lean_back_grip: float = 0.75
@export_range(0.0, 3.0, 0.01) var lean_back_turn: float = 0.8
@export_range(0.0, 3.0, 0.01) var lean_back_drag: float = 0.95

@export_group("Carving")
## Carving needs this much steer and forward lean, and this speed.
@export_range(0.0, 1.0, 0.01) var carve_steer: float = 0.8
@export_range(0.0, 1.0, 0.01) var carve_lean: float = 0.5
@export_range(0.0, 40.0, 0.1, "suffix:m/s") var carve_min_speed: float = 7.0
## Multipliers while carving, on top of the lean.
@export_range(0.0, 3.0, 0.01) var carve_turn: float = 1.25
@export_range(0.0, 3.0, 0.01) var carve_grip: float = 1.2
@export_range(0.0, 5.0, 0.01) var carve_drag: float = 1.2

@export_group("Air")
## Pitch rate from a full lean in the air, in rad/s.
@export_range(0.0, 10.0, 0.01, "suffix:rad/s") var air_pitch_rate: float = 1.4
## In the air, the lean stops pitching the craft further once the nose is this far above
## or below the horizon.
@export_range(0.0, 90.0, 0.1, "degrees") var air_pitch_limit: float = 50.0
## Yaw rate from full steer in the air.
@export_range(0.0, 10.0, 0.01, "suffix:rad/s") var air_yaw_rate: float = 0.6
## How quickly the air rates follow the stick, per second.
@export_range(0.0, 50.0, 0.1) var air_response: float = 4.0
## Seconds of air time over which the lean's pitch control fades in, so a short hop while
## carving with a forward lean doesn't dive the nose.
@export_range(0.0, 2.0, 0.01, "suffix:s") var air_control_delay: float = 0.35
## Bank into an air turn at full steer. The craft levels its roll toward this in the air.
@export_range(0.0, 60.0, 0.1, "degrees") var air_bank_angle: float = 10.0
## Roll levelling in the air: stiffness (per s²) and damping (per s).
@export_range(0.0, 100.0, 0.1) var air_roll_stiffness: float = 12.0
@export_range(0.0, 50.0, 0.1) var air_roll_damping: float = 5.0

@export_group("Stability")
## Resistance to pitching while in the water, in N m per rad/s.
@export_range(0.0, 10000.0, 1.0) var pitch_damping: float = 420.0
## Resistance to rolling while in the water, in N m per rad/s.
@export_range(0.0, 10000.0, 1.0) var roll_damping: float = 600.0
## Bow-up torque at top speed, so the craft runs nose-high as a planing hull does.
@export_range(0.0, 5000.0, 1.0) var trim_torque: float = 260.0
## Angular damping in the air, per second.
@export_range(0.0, 10.0, 0.01) var air_angular_damping: float = 0.3

@export_group("Crashes")
## A side or front impact against scenery that changes the craft's speed by more than this
## throws the rider off, in m/s. Walls and floating things never do.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var crash_impact_speed: float = 7.0
## The same for a collision with another craft.
@export_range(0.0, 50.0, 0.1, "suffix:m/s") var crash_craft_impact_speed: float = 9.0
## Landing after at least [member crash_landing_air_time] in the air throws the rider off if
## the nose is further below the water's surface than this...
@export_range(0.0, 90.0, 0.1, "degrees") var crash_landing_pitch: float = 25.0
## ...or the craft is rolled more than this...
@export_range(0.0, 90.0, 0.1, "degrees") var crash_landing_roll: float = 55.0
## ...or it is moving more than this far from where the nose points, above 8 m/s.
@export_range(0.0, 180.0, 0.1, "degrees") var crash_landing_slip: float = 75.0
@export_range(0.0, 3.0, 0.01, "suffix:s") var crash_landing_air_time: float = 0.3
## Upside down in the water this long throws the rider off.
@export_range(0.0, 5.0, 0.01, "suffix:s") var capsize_time: float = 0.35

@export_group("Remount")
## Share of the craft's velocity the rider keeps when thrown, and the extra upward and
## sideways speed (to the side the craft leans, or to the left).
@export_range(0.0, 1.5, 0.01) var throw_speed_share: float = 0.65
@export_range(0.0, 15.0, 0.1, "suffix:m/s") var throw_up_speed: float = 3.0
@export_range(0.0, 15.0, 0.1, "suffix:m/s") var throw_side_speed: float = 4.0
## How fast the rider swims back to the craft. Faster than a real swimmer, for the game.
@export_range(0.1, 10.0, 0.1, "suffix:m/s") var swim_speed: float = 2.0
## Seconds the rider spends coming up for air before swimming.
@export_range(0.0, 5.0, 0.01, "suffix:s") var surface_time: float = 0.6
## Seconds the rider takes to climb back on.
@export_range(0.1, 5.0, 0.01, "suffix:s") var mount_time: float = 0.9
## The rider climbs on within this distance of the seat.
@export_range(0.2, 5.0, 0.01, "suffix:m") var mount_reach: float = 1.4
## After this long in the water the rider is put back on the craft whatever the distance.
@export_range(1.0, 30.0, 0.1, "suffix:s") var max_swim_time: float = 7.0
## How quickly a craft without its rider slows down, per second (the engine cuts out).
@export_range(0.0, 10.0, 0.01) var riderless_brake: float = 1.1
## Pull of a riderless craft toward its swimming rider, per second squared per meter.
@export_range(0.0, 10.0, 0.01) var drift_to_rider: float = 0.5

@export_group("Stunts")
## A stunt can start once the craft has been this long in the air.
@export_range(0.0, 1.0, 0.01, "suffix:s") var stunt_min_air_time: float = 0.08
## Seconds each stunt takes. A stunt still going at touchdown fails (see
## [member stunt_landing_tolerance]), so a longer stunt needs a bigger jump.
@export_range(0.1, 3.0, 0.01, "suffix:s") var barrel_roll_time: float = 0.75
@export_range(0.1, 3.0, 0.01, "suffix:s") var backflip_time: float = 0.9
@export_range(0.1, 3.0, 0.01, "suffix:s") var spin_time: float = 0.7
@export_range(0.1, 3.0, 0.01, "suffix:s") var handstand_time: float = 0.9
## A roll, flip or spin this close to finished at touchdown still counts (the landing is
## untidy); further from it, the rider is thrown off.
@export_range(0.0, 180.0, 0.1, "degrees") var stunt_landing_tolerance: float = 45.0
## A handstand counts at touchdown once the rider is this far through it (back on the seat).
@export_range(0.0, 1.0, 0.01) var handstand_landing_progress: float = 0.85

@export_group("Landings")
## A landing after at least [member crash_landing_air_time] in the air is clean when the nose
## is no more than this far below the water's surface...
@export_range(0.0, 90.0, 0.1, "degrees") var clean_landing_pitch_down: float = 8.0
## ...and no more than this far above it...
@export_range(0.0, 90.0, 0.1, "degrees") var clean_landing_pitch_up: float = 28.0
## ...the craft is rolled no more than this...
@export_range(0.0, 90.0, 0.1, "degrees") var clean_landing_roll: float = 15.0
## ...and it moves no more than this far from where the nose points.
@export_range(0.0, 90.0, 0.1, "degrees") var clean_landing_slip: float = 20.0
## An untidy landing (between clean and a crash) costs this share of the speed when only just
## past clean, up to [member untidy_landing_max_loss] when nearly a crash.
@export_range(0.0, 1.0, 0.01) var untidy_landing_min_loss: float = 0.08
@export_range(0.0, 1.0, 0.01) var untidy_landing_max_loss: float = 0.35
