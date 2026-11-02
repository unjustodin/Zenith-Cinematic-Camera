extends RefCounted
## Tracking shots: follow something that moves (a train or one wagon, a car, a tank, a spidertron,
## a player, a robot, a rocket or a cargo pod, a group of biters) from behind, beside, above, or a
## fixed spot that turns to watch it, or ride on the front of a train or a car. N switches to the
## next one of the same kind, V to the next placement. The camera follows on springs, so the shot
## stays smooth even when what it follows jerks.

const Smooth := preload("smooth.gd")

const PLACEMENTS := ["behind", "beside", "above", "fixed", "ride"]
const PLACEMENT_NAMES := {"behind": "behind", "beside": "beside", "above": "above", "fixed": "from a fixed spot", "ride": "riding along"}
## What can be followed: kind -> the movers' prototype types.
const KINDS := {
	"train": ["locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon", "infinity-cargo-wagon"],
	"vehicle": ["car", "spider-vehicle"],
	"player": ["character"],
	"robot": ["logistic-robot", "construction-robot", "combat-robot"],
	"rocket": ["rocket-silo-rocket", "cargo-pod"],
	"biters": ["unit", "spider-unit"],
}
const KIND_NAMES := {"train": "train", "vehicle": "vehicle", "player": "player", "robot": "robot",
	"rocket": "rocket", "biters": "biter group", "wagon": "wagon"}
## Seconds what is followed may be gone (out of range, destroyed) before the shot ends.
const LOST_AFTER := 2.5
const GROUP_REACH := 28.0

var d  # the director
var takes_input := true
var kind := ""
var unit := 0  # the mover followed (a train's lead carriage, a wagon, a car...); 0: the client's own character for "player"
var train_id := 0
var placement := "behind"
## The fixed spot's place; INF until one is chosen (from where the camera is, when V picks it).
var fixed_spot := Vector3.INF
## Says so when what it follows is lost (idle mode just moves on).
var announce := true

var _cam := Smooth.Spring.new()
var _look := Smooth.Spring.new()
var _heading := 0.0  # yaw of the way it goes, smoothed
var _target := Vector3.ZERO
var _target_vel := Vector3.ZERO
var _length := 0.0
var _lost_for := 0.0
var _rocket_at := Vector3.INF
var _pose := Smooth.Pose.new()
var _ride_yaw := 0.0


func _init(director) -> void:
	d = director


func label() -> String:
	return "Following a %s %s" % [KIND_NAMES.get(kind, kind), PLACEMENT_NAMES.get(placement, placement)]


## Follows the nearest thing of a kind to the middle of the picture. False (with a message) when
## there's none near.
func track_nearest(what: String) -> bool:
	var at := _from_point()
	var best := _nearest(what, at)
	if best.is_empty():
		d.api.ui.message("No %s near enough to follow" % KIND_NAMES.get(what, what))
		return false
	_follow(what, best)
	return true


## Follows whatever moves nearest the middle of the picture (trains, vehicles and players first).
func track_any() -> bool:
	var at := _from_point()
	for what in ["train", "vehicle", "player", "rocket", "biters", "robot"]:
		var best := _nearest(what, at, 60.0)
		if not best.is_empty():
			_follow(what, best)
			return true
	d.api.ui.message("Nothing moving near the middle of the picture to follow")
	return false


## Follows one mover by its unit (idle mode), as `what`.
func track_unit(what: String, which: int, train := 0) -> void:
	_follow(what, {"unit": which, "train": train})


## A rocket rising from a silo at `silo` (or a cargo pod): filmed from a fixed spot near it.
func track_rocket(silo: Vector3) -> void:
	kind = "rocket"
	unit = 0
	_rocket_at = silo
	placement = "fixed"
	_reset_springs()
	fixed_spot = silo + Vector3(26.0, 6.0, 26.0)


## A group of biters near a point.
func track_group(at: Vector3) -> void:
	kind = "biters"
	unit = 0
	_target = at
	_reset_springs()


func next_placement() -> void:
	var i := (PLACEMENTS.find(placement) + 1) % PLACEMENTS.size()
	set_placement(PLACEMENTS[i])
	d.api.ui.message("Following %s" % PLACEMENT_NAMES[placement])


func set_placement(p: String, remember := true) -> void:
	if not p in PLACEMENTS:
		return
	placement = p
	if p == "fixed":
		fixed_spot = _cam.value if _cam.started else d.current_pose().pos
		if fixed_spot.distance_to(_target) > 90.0:
			fixed_spot = _target + Vector3(18.0, 9.0, 18.0)
	if remember:
		d.options["placement"] = p
		d.options_changed()


## N: the next one of the same kind (by its unit or train id), round and round.
func next_target() -> void:
	var list := _candidates(kind)
	if list.is_empty():
		d.api.ui.message("No other %s near" % KIND_NAMES.get(kind, kind))
		return
	var ids: Array = list.map(func(c: Dictionary) -> int: return int(c["key"]))
	ids.sort()
	var now := train_id if kind == "train" else unit
	var next: int = ids[0]
	for id in ids:
		if id > now:
			next = id
			break
	for c: Dictionary in list:
		if int(c["key"]) == next:
			_follow(kind, c)
			d.api.ui.message("Following the next %s" % KIND_NAMES.get(kind, kind))
			return


func start(from: Smooth.Pose) -> void:
	_pose = from.copy()
	_lost_for = 0.0
	_ride_yaw = from.yaw
	if placement == "" or not placement in PLACEMENTS:
		placement = str(d.options["placement"])
	var state := _resolve()
	if not state.is_empty():
		_target = state["pos"]
		_heading = _yaw_of(state["forward"])
		_length = float(state.get("length", 0.0))
	_cam.reset(from.pos)
	_look.reset(_target if not state.is_empty() else from.pos + from.forward() * 20.0)
	if placement == "fixed" and fixed_spot == Vector3.INF:
		set_placement("fixed", false)


func stop() -> void:
	pass


func focus_point():
	return _target


func update(delta: float) -> Smooth.Pose:
	var state := _resolve()
	if state.is_empty():
		_lost_for += delta
		if _lost_for > LOST_AFTER:
			if announce:
				d.api.ui.message("Lost the %s" % KIND_NAMES.get(kind, kind))
			return null
		return _pose
	_lost_for = 0.0
	var pos: Vector3 = state["pos"]
	if delta > 0.0:
		_target_vel = _target_vel.lerp((pos - _target) / delta, Smooth.blend(3.0, delta))
	_target = pos
	_length = float(state.get("length", _length))
	var flat_speed := Vector2(_target_vel.x, _target_vel.z).length()
	var fwd: Vector3 = state["forward"]
	if flat_speed > 0.6:
		fwd = Vector3(_target_vel.x, 0.0, _target_vel.z).normalized()
	_heading = lerp_angle(_heading, _yaw_of(fwd), Smooth.blend(2.0 if placement != "ride" else 5.0, delta))
	var f := Basis(Vector3.UP, _heading) * Vector3.FORWARD
	var right := Basis(Vector3.UP, _heading) * Vector3.RIGHT
	var goal := pos
	var look := pos + Vector3.UP
	var stiffness := 2.6
	match placement:
		"behind":
			goal = pos - f * (12.0 + _length) + Vector3.UP * (6.0 + _length * 0.15)
			look = pos + f * 6.0 + Vector3.UP
		"beside":
			goal = pos + right * (14.0 + _length * 0.4) + Vector3.UP * 4.0 - f * _length * 0.3
			look = pos - f * _length * 0.3 + Vector3.UP
		"above":
			goal = pos + Vector3.UP * (36.0 + _length) - f * 8.0
			look = pos + f * 4.0
		"fixed":
			goal = fixed_spot
			look = pos + Vector3.UP
			stiffness = 1.5
		"ride":
			var nose: Vector3 = state.get("nose", pos)
			goal = nose + f * 0.8 + Vector3.UP * 2.6
			look = goal + f * 30.0 - Vector3.UP * 3.0
			stiffness = 14.0
	if kind == "rocket":
		look = pos
	var cam := _cam.update(goal, stiffness, delta)
	var aim := _look.update(look, 6.0 if placement != "ride" else 16.0, delta)
	_pose.pos = cam
	_pose.fov = 0.0
	_pose.look_at_point(aim)
	return _pose


func input(event: InputEvent) -> bool:
	var keys = d.api.keys
	if keys.pressed(event, "next"):
		next_target()
		return true
	if keys.pressed(event, "placement"):
		next_placement()
		return true
	return false


# --- what is followed ---------------------------------------------------------------------------

## {pos (Vector3), forward (Vector3, flat), length (tiles behind the point), nose (ride-along's
## front point)} for what is followed now, or {} when it's gone.
func _resolve() -> Dictionary:
	var world = d.api.world
	match kind:
		"train":
			return _train_state()
		"player":
			if unit == 0:
				var c: Dictionary = world.character()
				if c.is_empty():
					return {}
				var p: Vector3 = c["position"]
				return {"pos": p + Vector3.UP * 0.9, "forward": c["forward"], "nose": p + c["forward"] * 0.6}
			return _mover_state(unit)
		"rocket":
			if _rocket_at != Vector3.INF:
				var best := Vector3.INF
				for r: Vector3 in world.rockets():
					if Vector2(r.x - _rocket_at.x, r.z - _rocket_at.z).length() < 6.0:
						best = r
				if best == Vector3.INF:
					return {"pos": _rocket_at + Vector3.UP * 8.0, "forward": Vector3.FORWARD} if _lost_for < LOST_AFTER * 4.0 else {}
				return {"pos": best + Vector3.UP * 8.0, "forward": Vector3.FORWARD}
			return _mover_state(unit)
		"biters":
			return _group_state()
		_:
			return _mover_state(unit)


func _mover_state(which: int) -> Dictionary:
	var m: Dictionary = d.api.world.mover(which)
	if m.is_empty():
		return {}
	var p: Vector3 = m["position"]
	var f: Vector3 = m["forward"]
	var half := 2.0 if str(m["type"]) in ["car", "spider-vehicle"] else 0.5
	return {"pos": p + Vector3.UP * 0.8, "forward": f, "nose": p + f * half}


## A train: its carriages' places, the way it travels, its length, its leading end.
func _train_state() -> Dictionary:
	var trains: Array = d.api.world.trains()
	var t: Dictionary = {}
	for tr: Dictionary in trains:
		if int(tr["id"]) == train_id:
			t = tr
	if t.is_empty():
		var lone := _mover_state(unit)  # out of the list (beyond the entity distance): the carriage alone
		return lone
	var points: Array = []
	for u in t["carriages"]:
		var m: Dictionary = d.api.world.mover(int(u))
		if not m.is_empty():
			points.append(m)
	if points.is_empty():
		return {}
	var backwards := float(t["speed"]) < 0.0
	var lead: Dictionary = points[-1] if backwards else points[0]
	var tail: Dictionary = points[0] if backwards else points[-1]
	unit = int(lead["unit"])
	var lp: Vector3 = lead["position"]
	var tp: Vector3 = tail["position"]
	var f: Vector3 = lead["forward"] * (-1.0 if backwards else 1.0)
	if points.size() > 1:
		var along := lp - tp
		along.y = 0.0
		if along.length() > 0.5:
			f = along.normalized()
	return {"pos": lp + Vector3.UP * 1.2, "forward": f, "length": lp.distance_to(tp), "nose": lp + f * 3.4}


## A group of biters: the middle of those near where the group was.
func _group_state() -> Dictionary:
	var sum := Vector3.ZERO
	var n := 0
	for m: Dictionary in d.api.world.movers(KINDS["biters"]):
		var p: Vector3 = m["position"]
		if Vector2(p.x - _target.x, p.z - _target.z).length() <= GROUP_REACH:
			sum += p
			n += 1
	if n == 0:
		return {}
	var mid := sum / n
	var f := _target_vel if _target_vel.length() > 0.3 else Basis(Vector3.UP, _heading) * Vector3.FORWARD
	f.y = 0.0
	return {"pos": mid + Vector3.UP * 0.8, "forward": f.normalized(), "length": minf(12.0, 2.0 + n * 0.3)}


## [{key (unit, or train id), unit, train, pos}] of a kind near the focus.
func _candidates(what: String) -> Array:
	var out: Array = []
	var world = d.api.world
	if what == "train":
		for t: Dictionary in world.trains():
			var cars: Array = t["carriages"]
			if cars.is_empty():
				continue
			var m: Dictionary = world.mover(int(cars[0]))
			if not m.is_empty():
				out.append({"key": int(t["id"]), "unit": int(cars[0]), "train": int(t["id"]), "pos": m["position"]})
		return out
	if what == "biters":
		# One candidate per group: biters within GROUP_REACH of one already counted join it.
		for m: Dictionary in world.movers(KINDS["biters"]):
			var p: Vector3 = m["position"]
			var joined := false
			for c: Dictionary in out:
				if (c["pos"] as Vector3).distance_to(p) <= GROUP_REACH:
					joined = true
					break
			if not joined:
				out.append({"key": int(m["unit"]), "unit": int(m["unit"]), "train": 0, "pos": p})
		return out
	if what == "player":
		var me: Dictionary = world.character()
		if not me.is_empty() and bool(me["visible"]):
			out.append({"key": 0, "unit": 0, "train": 0, "pos": me["position"]})
	for m: Dictionary in world.movers(KINDS.get(what, [])):
		out.append({"key": int(m["unit"]), "unit": int(m["unit"]), "train": 0, "pos": m["position"]})
	return out


func _nearest(what: String, at: Vector3, reach := 400.0) -> Dictionary:
	var best := {}
	var best_d := reach
	for c: Dictionary in _candidates(what):
		var p: Vector3 = c["pos"]
		var dist := Vector2(p.x - at.x, p.z - at.z).length()
		if dist < best_d:
			best_d = dist
			best = c
	return best


func _follow(what: String, c: Dictionary) -> void:
	kind = what
	unit = int(c.get("unit", 0))
	train_id = int(c.get("train", 0))
	_rocket_at = Vector3.INF
	if what == "train" and train_id == 0:
		train_id = d.api.world.train_of(unit)
	if what == "rocket":
		var m: Dictionary = d.api.world.mover(unit)
		if not m.is_empty() and str(m["type"]) == "rocket-silo-rocket":
			_rocket_at = m["position"]
	if what == "biters":
		_target = c.get("pos", _target)
	_reset_springs()


func _reset_springs() -> void:
	_lost_for = 0.0
	_target_vel = Vector3.ZERO
	var state := _resolve()
	if not state.is_empty():
		_target = state["pos"]
		_heading = _yaw_of(state["forward"])
		_length = float(state.get("length", 0.0))
	_cam.started = false
	_look.started = false
	fixed_spot = Vector3.INF
	if d.mode == self:
		var now: Smooth.Pose = d.current_pose()
		_cam.reset(now.pos)
		_look.reset(now.pos + now.forward() * now.pos.distance_to(_target))
		if placement == "fixed":
			set_placement("fixed", false)


## Where to look for things to follow: the ground in the middle of the picture, else the focus.
func _from_point() -> Vector3:
	var g = d.api.camera.center_ground()
	if g is Vector3:
		return g
	var f: Vector2 = d.api.world.focus()
	return Vector3(f.x, 0.0, f.y)


static func _yaw_of(f: Vector3) -> float:
	return atan2(-f.x, -f.z)
