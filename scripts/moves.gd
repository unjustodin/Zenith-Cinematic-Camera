extends RefCounted
## Preset moves round the point in the middle of the picture: orbit, fly-over, dolly (a straight
## line sideways), crane (straight up), push in and pull out. Each has a speed and a length, starts
## and stops smoothly, and can loop (an orbit goes on round; the others go there and back).

const Smooth := preload("smooth.gd")

const KINDS := ["orbit", "flyover", "dolly", "crane", "push_in", "pull_out"]
const NAMES := {"orbit": "Orbit", "flyover": "Fly-over", "dolly": "Dolly", "crane": "Crane up",
	"push_in": "Push in", "pull_out": "Pull out"}
## Seconds over which a move gets up to speed and slows to a stop.
const RAMP := 2.5

var d  # the director
var takes_input := true
var kind := "orbit"
var center := Vector3.ZERO
## The point to move round for the next start() (idle mode), instead of the middle of the picture.
var forced_center = null
var _from := Smooth.Pose.new()
var _t := 0.0
var _leg := 0  # a looping straight move: even legs out, odd ones back
var _pose := Smooth.Pose.new()
## The straight moves' ends, and the orbit's radius, height and starting angle.
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _radius := 30.0
var _height := 20.0
var _angle0 := 0.0
var _fixed_look := false


func _init(director) -> void:
	d = director


func label() -> String:
	return "%s (%s)" % [NAMES.get(kind, kind), "looping" if bool(d.options["move_loop"]) else "once"]


## Orbit speeds are degrees a second (lengths degrees); the others tiles a second (lengths tiles).
func _speed() -> float:
	return float(d.options["move_speed"]) * (1.5 if kind == "orbit" else 1.0)


func _length() -> float:
	return float(d.options["move_length"]) * (6.0 if kind == "orbit" else 1.0)


func start(from: Smooth.Pose) -> void:
	_from = from.copy()
	_from.ortho = 0.0
	_t = 0.0
	_leg = 0
	var g = forced_center if forced_center is Vector3 else d.api.camera.center_ground()
	forced_center = null
	center = g if g is Vector3 and (g as Vector3).distance_to(from.pos) < 600.0 else from.pos + from.forward() * 40.0
	center.y = 0.0
	var flat := Vector3(from.pos.x - center.x, 0.0, from.pos.z - center.z)
	var f := from.forward()
	var f_flat := Vector3(f.x, 0.0, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else Vector3.FORWARD
	var right := f_flat.cross(Vector3.UP).normalized()
	_fixed_look = false
	match kind:
		"orbit":
			_radius = maxf(flat.length(), 15.0)
			_height = maxf(from.pos.y, 8.0)
			_angle0 = atan2(flat.x, flat.z)
		"flyover":
			_height = maxf(from.pos.y, 25.0)
			_a = center - f_flat * _length() * 0.5 + Vector3.UP * _height
			_b = center + f_flat * _length() * 0.5 + Vector3.UP * _height
		"dolly":
			_a = from.pos
			_b = from.pos + right * _length()
			_fixed_look = true
		"crane":
			_a = from.pos
			_b = from.pos + Vector3.UP * _length()
		"push_in":
			var toward := (center - from.pos).normalized()
			_a = from.pos
			_b = from.pos + toward * minf(_length(), maxf(0.0, from.pos.distance_to(center) - 10.0))
		"pull_out":
			var away := (from.pos - center).normalized()
			_a = from.pos
			_b = from.pos + away * _length()


func stop() -> void:
	pass


func focus_point():
	return center


func update(delta: float) -> Smooth.Pose:
	_t += delta
	var loop := bool(d.options["move_loop"])
	_pose.fov = 0.0
	if kind == "orbit":
		var turned: float
		if loop:
			turned = Smooth.ramp_distance(_t, _speed(), RAMP)
		else:
			var m := Smooth.ramped_move(_t, _length(), _speed(), RAMP)
			turned = m[0]
			if _t >= float(m[1]):
				return null
		var a := _angle0 + deg_to_rad(turned)
		_pose.pos = center + Vector3(sin(a) * _radius, _height, cos(a) * _radius)
		_pose.look_at_point(center)
		return _pose
	var length := _a.distance_to(_b)
	if length < 0.01:
		return null
	var mv := Smooth.ramped_move(_t, length, _speed(), RAMP)
	var s: float = mv[0] / length
	if _t >= float(mv[1]):
		if not loop:
			return null
		_t = 0.0
		_leg += 1
	if _leg % 2 == 1:
		s = 1.0 - s
	_pose.pos = _a.lerp(_b, s)
	if _fixed_look:
		_pose.yaw = _from.yaw
		_pose.pitch = _from.pitch
	elif kind == "flyover":
		var dir := (_b - _a).normalized() * (-1.0 if _leg % 2 == 1 else 1.0)
		_pose.yaw = atan2(-dir.x, -dir.z)
		_pose.pitch = deg_to_rad(-35.0)
	else:
		_pose.look_at_point(center)
	return _pose


func input(_event: InputEvent) -> bool:
	return false
