extends RefCounted
## Idle mode: the camera picks something interesting, films it for a while and moves on: a rocket
## launch, a fight at the walls, a train leaving a station, trains, vehicles and players on the
## move, robots at work, a busy part of the base or a belt line. Started on demand, or by itself
## after a while with no input (then any key or the mouse ends it). For a second monitor or a
## stream's break screen.

const Smooth := preload("smooth.gd")

## Seconds between two shots blend.
const BLEND := 3.0

var d  # the director
var takes_input := true
var automatic := false  # started by itself: any input ends it
var subject := ""

var _shot = null  # the tracking or preset move filming now
var _left := 0.0
var _last_subject := ""
var _blend_from: Smooth.Pose = null
var _blend_t := 0.0
var _pose := Smooth.Pose.new()
var _tracking
var _moves


func _init(director, tracking_mode, moves_mode) -> void:
	d = director
	_tracking = tracking_mode
	_moves = moves_mode


func label() -> String:
	return "Idle: %s" % (subject if subject != "" else "looking for something")


func start(from: Smooth.Pose) -> void:
	_pose = from.copy()
	_last_subject = ""
	_pick(from)


func stop() -> void:
	if _shot != null:
		_shot.stop()
	_shot = null
	subject = ""


func focus_point():
	return _shot.focus_point() if _shot != null else null


func update(delta: float) -> Smooth.Pose:
	_left -= delta
	var p: Smooth.Pose = _shot.update(delta) if _shot != null else null
	if p == null or _left <= 0.0:
		_pick(_pose)
		p = _shot.update(0.0) if _shot != null else null
		if p == null:
			return _pose
	if _blend_from != null:
		_blend_t += delta
		var t := Smooth.ease_in_out(_blend_t / BLEND)
		p = Smooth.mix(_blend_from, p, t)
		if _blend_t >= BLEND:
			_blend_from = null
	_pose = p.copy()
	return _pose


func input(_event: InputEvent) -> bool:
	return false


## The next shot: an event worth seeing first, else something chosen at random (not the same kind
## twice running).
func _pick(from: Smooth.Pose) -> void:
	if _shot != null:
		_shot.stop()
	_shot = null
	_blend_from = from.copy()
	_blend_t = 0.0
	var length := float(d.options["idle_shot"])
	var events = d.api.events
	for e: Dictionary in events.recent(25.0):
		if e["kind"] == "rocket_launched" and float(e["age"]) < 15.0 and _last_subject != "rocket":
			_tracking.track_rocket(e["position"])
			_use(_tracking, "a rocket launch", "rocket", length + 8.0)
			return
	var fights: Array = events.fights()
	if not fights.is_empty() and _last_subject != "fight":
		var biggest: Dictionary = fights[0]
		for f: Dictionary in fights:
			if int(f["size"]) > int(biggest["size"]):
				biggest = f
		_tracking.track_group(biggest["position"])
		_tracking.placement = "fixed"
		_tracking.fixed_spot = (biggest["position"] as Vector3) + Vector3(22.0, 14.0, 22.0)
		_use(_tracking, "a fight", "fight", length)
		return
	for e: Dictionary in events.recent(20.0):
		if e["kind"] == "train_departed" and _last_subject != "departure":
			var cars := _train_units(int(e["train_id"]))
			if not cars.is_empty():
				_tracking.track_unit("train", cars[0], int(e["train_id"]))
				_tracking.placement = ["behind", "beside", "ride"].pick_random()
				_use(_tracking, "a train leaving a station", "departure", length)
				return
	var options: Array = []
	var moving_trains: Array = d.api.world.trains().filter(func(t: Dictionary) -> bool: return absf(float(t["speed"])) > 0.05)
	if not moving_trains.is_empty():
		options.append(["train", 3])
	if not d.api.world.movers(["car", "spider-vehicle"]).is_empty():
		options.append(["vehicle", 2])
	if not d.api.world.movers(["character"]).is_empty():
		options.append(["player", 2])
	if d.api.world.movers(["logistic-robot", "construction-robot"]).size() >= 3:
		options.append(["robot", 1])
	options.append(["busy", 2])
	options.append(["belts", 1])
	options.append(["flyover", 1])
	options = options.filter(func(o: Array) -> bool: return o[0] != _last_subject)
	var total := 0
	for o in options:
		total += int(o[1])
	var roll := randi() % maxi(total, 1)
	var chosen := "busy"
	for o in options:
		roll -= int(o[1])
		if roll < 0:
			chosen = str(o[0])
			break
	match chosen:
		"train":
			var t: Dictionary = moving_trains.pick_random()
			_tracking.track_unit("train", int(t["carriages"][0]), int(t["id"]))
			_tracking.placement = ["behind", "beside", "above", "ride"].pick_random()
			_use(_tracking, "a train", "train", length)
		"vehicle", "player", "robot":
			var types: Array = {"vehicle": ["car", "spider-vehicle"], "player": ["character"], "robot": ["logistic-robot", "construction-robot"]}[chosen]
			var m: Dictionary = d.api.world.movers(types).pick_random()
			_tracking.track_unit(chosen, int(m["unit"]))
			_tracking.placement = ["behind", "beside", "fixed"].pick_random() if chosen != "robot" else "behind"
			_use(_tracking, "a " + chosen, chosen, length * (0.6 if chosen == "robot" else 1.0))
		"busy", "belts":
			var at = _busiest(chosen == "belts")
			_orbit_round(at if at is Vector3 else _focus3(), from)
			_use(_moves, "the belts" if chosen == "belts" else "a busy corner of the base", chosen, length, false)
		_:
			_moves.kind = "flyover"
			_moves.forced_center = _focus3()
			_moves.start(_flyover_from(from))
			_use(_moves, "a fly-over", "flyover", length, false)


func _use(shot, what: String, kind: String, seconds: float, start := true) -> void:
	_shot = shot
	_tracking.announce = false
	if start:
		shot.start(_blend_from)
	subject = what
	_last_subject = kind
	_left = seconds


func _train_units(id: int) -> Array:
	for t: Dictionary in d.api.world.trains():
		if int(t["id"]) == id:
			return t["carriages"]
	return []


## An orbit round a point, from a spot that frames it.
func _orbit_round(at: Vector3, from: Smooth.Pose) -> void:
	var start := Smooth.Pose.new()
	var off := Vector3(from.pos.x - at.x, 0.0, from.pos.z - at.z)
	if off.length() < 1.0:
		off = Vector3(0.0, 0.0, 1.0)
	start.pos = at + off.normalized() * 34.0 + Vector3.UP * 22.0
	start.look_at_point(at)
	_moves.kind = "orbit"
	_moves.forced_center = at
	_moves.start(start)


func _flyover_from(from: Smooth.Pose) -> Smooth.Pose:
	var f := _focus3()
	var p := Smooth.Pose.new()
	var a := randf() * TAU
	p.pos = f + Vector3(sin(a), 0.0, cos(a)) * 50.0 + Vector3.UP * maxf(from.pos.y, 30.0)
	p.look_at_point(f)
	return p


## The middle of the busiest of up to 40 chunks round the focus: working machines, or belts.
func _busiest(belts: bool):
	var f: Vector2 = d.api.world.focus()
	var chunks: Array = d.api.world.chunks()
	chunks = chunks.filter(func(c: Vector2i) -> bool: return Vector2(c.x * 32 + 16, c.y * 32 + 16).distance_to(f) < 200.0)
	chunks.shuffle()
	var best = null
	var best_score := 0
	for c: Vector2i in chunks.slice(0, 40):
		var score := 0
		var sum := Vector2.ZERO
		var types: Array = ["transport-belt", "underground-belt", "splitter"] if belts else []
		for e: Dictionary in d.api.world.entities_in_chunk(c, types):
			if belts or e["working"] == true:
				score += 1
				sum += e["position"]
		if score > best_score:
			best_score = score
			best = Vector3(sum.x / score, 0.0, sum.y / score)
	return best if best_score >= (12 if belts else 4) else null


func _focus3() -> Vector3:
	var f: Vector2 = d.api.world.focus()
	return Vector3(f.x, 0.0, f.y)
