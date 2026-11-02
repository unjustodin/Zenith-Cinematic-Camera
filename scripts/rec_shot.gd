extends RefCounted
## The camera mode's shot, which the recorder films and the camera view shows: a camera circling
## above a point at a distance, turning at the spin speed. The point is a player (yours or another
## one) or a fixed spot. With combat zoom on, a fight (enemies attacking, turrets firing: Zenith's
## fight events) takes over: the camera glides there, closer, and circles slowly above it until the
## fight has been quiet for a while, then glides back. Periodic angle swaps pick a new angle every
## few seconds and glide to it.

const Smooth := preload("smooth.gd")

## Seconds a glide to a fight, back from it, or to a new angle takes (about).
const GLIDE := 2.5
## Tilts (degrees down) the periodic swaps choose from.
const SWAP_TILTS := [32.0, 40.0, 48.0, 58.0, 68.0]
## A fight further than this from what the shot follows is left alone (the world is only drawn round
## Zenith's focus, and Zenith only sees fights there).
const COMBAT_REACH := 200.0

var d  # the director
## The fixed spot (y 0), when the shot stays on one.
var spot := Vector3.INF
## The fight filmed now (Vector3), or null.
var fight = null

var _target := Smooth.Spring.new()
var _yaw := 0.0
var _tilt := 45.0  # degrees down
var _distance := -1.0
var _swap_clock := 0.0
var _swap_from_yaw := 0.0
var _swap_from_tilt := 0.0
var _swap_to_yaw := 0.0
var _swap_to_tilt := 0.0
var _swap_t := -1.0
var _pose := Smooth.Pose.new()
var _since_switch := 99.0
var _was_fight := false
var _rng := RandomNumberGenerator.new()


func _init(director) -> void:
	d = director
	_rng.randomize()


## Starts afresh at the target (no glide in from the old one).
func reset() -> void:
	_target.started = false
	_distance = -1.0
	_swap_clock = 0.0
	_swap_t = -1.0
	_tilt = float(d.options["rec_tilt"])


func label() -> String:
	if fight != null:
		return "Combat zoom: circling a fight"
	if str(d.options["rec_follow"]) == "spot":
		return "Circling a spot"
	return "Following %s" % _player_label()


## Stays on the ground in the middle of the picture (or the character, when there is none).
func set_spot_here() -> void:
	var g = d.api.camera.center_ground()
	if g is Vector3:
		spot = g
	else:
		spot = _player_position()
	spot.y = 0.0


## Where the shot's point is when nothing is fighting: the followed player, or the spot.
func base_target() -> Vector3:
	if str(d.options["rec_follow"]) == "spot":
		if spot == Vector3.INF:
			set_spot_here()
		return spot
	return _player_position()


## The pose for this frame (also advances the spin, swaps and glides).
func update(delta: float) -> Smooth.Pose:
	var base := base_target()
	fight = _pick_fight(base) if bool(d.options["rec_combat"]) else null
	var goal: Vector3 = fight if fight != null else base
	var want_distance := float(d.options["rec_combat_distance"]) if fight != null else float(d.options["rec_distance"])
	var spin := float(d.options["rec_combat_spin"]) if fight != null else float(d.options["rec_spin"])
	if (fight != null) != _was_fight:
		_was_fight = fight != null
		_since_switch = 0.0
	_since_switch += delta
	# Slow and smooth just after switching to a fight or back; then it keeps up with a walking player.
	var target := _target.update(goal, lerpf(4.0 / GLIDE, 3.0, clampf(_since_switch / GLIDE, 0.0, 1.0)), delta)
	_distance = want_distance if _distance < 0.0 else lerpf(_distance, want_distance, Smooth.blend(1.6, delta))
	_yaw = fposmod(_yaw + deg_to_rad(spin) * delta, TAU)
	_update_swaps(delta)
	var tilt := deg_to_rad(_tilt)
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw)) * cos(tilt) + Vector3.UP * sin(tilt)
	_pose.pos = target + back * _distance
	_pose.look_at_point(target)
	_pose.fov = float(d.options["fov"])
	_pose.ortho = 0.0
	return _pose


func pose() -> Smooth.Pose:
	return _pose


## Every N seconds a new angle (round and down), glided to.
func _update_swaps(delta: float) -> void:
	var settled := float(d.options["rec_tilt"])
	if not bool(d.options["rec_swaps"]):
		_swap_t = -1.0
		_tilt = lerpf(_tilt, settled, Smooth.blend(1.5, delta))
		return
	if _swap_t >= 0.0:
		_swap_t += delta
		var k := Smooth.ease_in_out(_swap_t / GLIDE)
		_yaw = lerp_angle(_swap_from_yaw, _swap_to_yaw, k)
		_tilt = lerpf(_swap_from_tilt, _swap_to_tilt, k)
		if _swap_t >= GLIDE:
			_swap_t = -1.0
		return
	_swap_clock += delta
	if _swap_clock < maxf(float(d.options["rec_swap_every"]), GLIDE + 1.0):
		return
	_swap_clock = 0.0
	_swap_t = 0.0
	_swap_from_yaw = _yaw
	_swap_from_tilt = _tilt
	_swap_to_yaw = fposmod(_yaw + deg_to_rad(_rng.randf_range(70.0, 160.0)) * (1.0 if _rng.randf() < 0.5 else -1.0), TAU)
	var tilts: Array = SWAP_TILTS.filter(func(t: float) -> bool: return absf(t - _tilt) > 6.0)
	_swap_to_tilt = float(tilts[_rng.randi() % tilts.size()]) if not tilts.is_empty() else settled


## The fight to film: the biggest near what the shot follows (sticking with the one filmed while it
## lasts, so two fights don't make the camera swing back and forth).
func _pick_fight(near: Vector3):
	var best = null
	var best_size := -1
	for f: Dictionary in d.api.events.fights():
		var at: Vector3 = f["position"]
		if Vector2(at.x - near.x, at.z - near.z).length() > COMBAT_REACH:
			continue
		var n := int(f["size"])
		if fight is Vector3 and Vector2(at.x - fight.x, at.z - fight.z).length() < 48.0:
			n += 1000  # the one being filmed
		if n > best_size:
			best_size = n
			best = Vector3(at.x, 0.0, at.z)
	return best


func _player_position() -> Vector3:
	var who := str(d.options["rec_player"])
	if who != "":
		for p: Dictionary in d.api.world.players():
			if str(p["name"]) == who and not bool(p["me"]):
				var m: Dictionary = d.api.world.mover(int(p["unit"]))
				if not m.is_empty():
					var at: Vector3 = m["position"]
					return Vector3(at.x, 0.0, at.z)
	var me: Dictionary = d.api.world.character()
	if me.has("position"):
		var at: Vector3 = me["position"]
		return Vector3(at.x, 0.0, at.z)
	var f: Vector2 = d.api.world.focus()
	return Vector3(f.x, 0.0, f.y)


func _player_label() -> String:
	var who := str(d.options["rec_player"])
	return "you" if who == "" else who
