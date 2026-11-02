extends RefCounted
## Paths and keyframes: points placed round the base, each the camera's position, direction and
## field of view; the camera glides through them on a smooth curve (centripetal Catmull-Rom), at an
## even speed along it, easing in at the start and out at the end, or round and round as a loop.
## Paths are kept with the save (api.storage) and can be played again after the base changes.

const Smooth := preload("smooth.gd")

## Curve samples per stretch between two points (for an even speed along it).
const SAMPLES := 48
const RAMP := 2.0

var d  # the director
var takes_input := true
## The points: [{pos (Vector3), yaw, pitch, fov}].
var points: Array = []
var name := "Path 1"

var _t := 0.0
var _lengths := PackedFloat32Array()  # cumulative length at each sample
var _keys: Array = []  # [segment, u] at each sample
var _total := 0.0
var _pose := Smooth.Pose.new()
var _loop := false


func _init(director) -> void:
	d = director


func label() -> String:
	return "Path \"%s\", %d points" % [name, points.size()]


func add_point(p: Smooth.Pose) -> void:
	points.append({"pos": p.pos, "yaw": p.yaw, "pitch": p.pitch, "fov": p.fov if p.fov > 0.0 else float(d.options["fov"])})


func remove_last() -> void:
	if not points.is_empty():
		points.pop_back()


func clear() -> void:
	points.clear()


func can_play() -> bool:
	return points.size() >= 2


func start(_from: Smooth.Pose) -> void:
	_t = 0.0
	_loop = bool(d.options["path_loop"]) and points.size() >= 3
	_unwrap_yaws()
	_build()


func stop() -> void:
	pass


func focus_point():
	return null


func update(delta: float) -> Smooth.Pose:
	if points.size() < 2 or _total <= 0.0:
		return null
	_t += delta
	var speed := float(d.options["path_speed"])
	var s: float
	if _loop:
		s = fposmod(Smooth.ramp_distance(_t, speed, RAMP), _total)
	else:
		var m := Smooth.ramped_move(_t, _total, speed, RAMP)
		s = m[0]
		if _t >= float(m[1]):
			return null
	_sample(s)
	return _pose


func input(_event: InputEvent) -> bool:
	return false


## Saved form (plain JSON): {"name", "points": [[x, y, z, yaw, pitch, fov], ...]}.
func to_data() -> Dictionary:
	var out: Array = []
	for p: Dictionary in points:
		var v: Vector3 = p["pos"]
		out.append([v.x, v.y, v.z, p["yaw"], p["pitch"], p["fov"]])
	return {"name": name, "points": out}


func from_data(data: Dictionary) -> void:
	points.clear()
	name = str(data.get("name", "Path"))
	for r in data.get("points", []):
		if r is Array and r.size() >= 6:
			points.append({"pos": Vector3(float(r[0]), float(r[1]), float(r[2])), "yaw": float(r[3]),
				"pitch": float(r[4]), "fov": float(r[5])})


## Yaws made continuous from point to point, so the camera turns the short way.
func _unwrap_yaws() -> void:
	for i in range(1, points.size()):
		var prev := float(points[i - 1]["yaw"])
		points[i]["yaw"] = prev + wrapf(float(points[i]["yaw"]) - prev, -PI, PI)


func _count() -> int:
	return points.size() if _loop else points.size() - 1


## The four points round stretch i (from point i to i+1), ends doubled when not looping.
func _ctrl(i: int) -> Array:
	var n := points.size()
	var out: Array = []
	for k in [i - 1, i, i + 1, i + 2]:
		if _loop:
			out.append(points[posmod(k, n)])
		elif k < 0:
			out.append(_mirror(points[0], points[1]))
		elif k >= n:
			out.append(_mirror(points[n - 1], points[n - 2]))
		else:
			out.append(points[k])
	if _loop:
		# A loop's yaws may jump a whole turn at the seam: keep the four continuous.
		for j in range(1, 4):
			var prev := float(out[j - 1]["yaw"])
			var p: Dictionary = (out[j] as Dictionary).duplicate()
			p["yaw"] = prev + wrapf(float(p["yaw"]) - prev, -PI, PI)
			out[j] = p
	return out


static func _mirror(end: Dictionary, inner: Dictionary) -> Dictionary:
	var e: Vector3 = end["pos"]
	var i: Vector3 = inner["pos"]
	return {"pos": e * 2.0 - i, "yaw": float(end["yaw"]) * 2.0 - float(inner["yaw"]),
		"pitch": float(end["pitch"]) * 2.0 - float(inner["pitch"]), "fov": float(end["fov"]) * 2.0 - float(inner["fov"])}


func _build() -> void:
	_lengths = PackedFloat32Array()
	_keys = []
	_total = 0.0
	var last := Vector3.INF
	for i in _count():
		var c := _ctrl(i)
		for k in SAMPLES + (1 if i == _count() - 1 else 0):
			var u := float(k) / SAMPLES
			var p := _position(c, u)
			if last != Vector3.INF:
				_total += last.distance_to(p)
			last = p
			_lengths.append(_total)
			_keys.append([i, u])


## The pose at distance s along the curve.
func _sample(s: float) -> void:
	var lo := 0
	var hi := _lengths.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _lengths[mid] <= s:
			lo = mid
		else:
			hi = mid
	var span := _lengths[hi] - _lengths[lo]
	var f := (s - _lengths[lo]) / span if span > 0.0001 else 0.0
	var a: Array = _keys[lo]
	var b: Array = _keys[hi]
	var seg := int(a[0])
	var u := lerpf(float(a[1]), float(b[1]) if int(b[0]) == seg else 1.0, f)
	var c := _ctrl(seg)
	_pose.pos = _position(c, u)
	_pose.yaw = _cr(float(c[0]["yaw"]), float(c[1]["yaw"]), float(c[2]["yaw"]), float(c[3]["yaw"]), u)
	_pose.pitch = _cr(float(c[0]["pitch"]), float(c[1]["pitch"]), float(c[2]["pitch"]), float(c[3]["pitch"]), u)
	_pose.fov = clampf(_cr(float(c[0]["fov"]), float(c[1]["fov"]), float(c[2]["fov"]), float(c[3]["fov"]), u), 5.0, 120.0)


## Centripetal Catmull-Rom (no loops or cusps where points bunch up).
static func _position(c: Array, u: float) -> Vector3:
	var p0: Vector3 = c[0]["pos"]
	var p1: Vector3 = c[1]["pos"]
	var p2: Vector3 = c[2]["pos"]
	var p3: Vector3 = c[3]["pos"]
	var t0 := 0.0
	var t1 := t0 + pow(maxf(p0.distance_to(p1), 0.0001), 0.5)
	var t2 := t1 + pow(maxf(p1.distance_to(p2), 0.0001), 0.5)
	var t3 := t2 + pow(maxf(p2.distance_to(p3), 0.0001), 0.5)
	var t := lerpf(t1, t2, u)
	var a1 := p0 * ((t1 - t) / (t1 - t0)) + p1 * ((t - t0) / (t1 - t0))
	var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
	var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
	var b1 := a1 * ((t2 - t) / (t2 - t0)) + a2 * ((t - t0) / (t2 - t0))
	var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
	return b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1))


## Uniform Catmull-Rom for the angles and the field of view.
static func _cr(a: float, b: float, c: float, e: float, u: float) -> float:
	var u2 := u * u
	var u3 := u2 * u
	return 0.5 * ((2.0 * b) + (-a + c) * u + (2.0 * a - 5.0 * b + 4.0 * c - e) * u2 + (-a + 3.0 * b - 3.0 * c + e) * u3)
