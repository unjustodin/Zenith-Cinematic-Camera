extends RefCounted
## The free camera: fly anywhere away from the character at a fixed speed (+ and - change it), look
## with the mouse, and O to orbit slowly round the point in the middle of the screen (+ and - then
## change the orbit's speed). Every move eases in and out: speed, turning, the orbit, the zoom.

const Smooth := preload("smooth.gd")

## Flying speeds, tiles a second, and orbit speeds, degrees a second (+ and - step through them).
const SPEEDS := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0]
const ORBIT_SPEEDS := [1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0]
## How quickly the camera reaches a new speed (about a second) and turns to where the mouse points.
const ACCELERATION := 2.2
const LOOK_RATE := 9.0
const LOOK_DEGREES_PER_PIXEL := 0.1
const ORBIT_RAMP := 1.4
const FOV_STEP := 3.0

var d  # the director
var takes_input := true
var pose := Smooth.Pose.new()
var velocity := Vector3.ZERO
var yaw_goal := 0.0
var pitch_goal := 0.0
var fov_goal := 0.0
var orbiting := false
var orbit_pivot := Vector3.ZERO
var orbit_rate := 0.0  # degrees a second now, easing towards the chosen speed (or 0 when stopping)
var orbit_sign := 1.0


func _init(director) -> void:
	d = director


func label() -> String:
	if orbiting:
		return "Orbit, %s°/s" % _num(ORBIT_SPEEDS[int(d.options["orbit_speed"])])
	return "Free camera, %s tiles/s" % _num(SPEEDS[int(d.options["speed"])])


func start(from: Smooth.Pose) -> void:
	pose = from.copy()
	pose.ortho = 0.0
	velocity = Vector3.ZERO
	yaw_goal = pose.yaw
	pitch_goal = pose.pitch
	fov_goal = from.fov if from.fov > 0.0 else float(d.options["fov"])
	pose.fov = fov_goal
	orbiting = false
	orbit_rate = 0.0
	d.api.camera.capture_mouse(true)


func stop() -> void:
	orbiting = false
	orbit_rate = 0.0
	d.api.camera.capture_mouse(false)


func focus_point():
	return orbit_pivot if orbiting else null


func update(delta: float) -> Smooth.Pose:
	var keys = d.api.keys
	var ahead := float(int(keys.held("forward"))) - float(int(keys.held("back")))
	var side := float(int(keys.held("right"))) - float(int(keys.held("left")))
	var lift := float(int(keys.held("up"))) - float(int(keys.held("down")))
	var moving := ahead != 0.0 or side != 0.0 or lift != 0.0
	var speed: float = SPEEDS[int(d.options["speed"])]
	var flat := Basis(Vector3.UP, pose.yaw)
	var want := flat * Vector3(side, 0.0, -ahead)
	if want.length() > 1.0:
		want = want.normalized()
	want.y = lift
	velocity = velocity.lerp(want * speed, Smooth.blend(ACCELERATION, delta))
	if moving and orbiting:
		orbiting = false  # flying away from the pivot ends the orbit, which slows to a stop
	var orbit_goal: float = ORBIT_SPEEDS[int(d.options["orbit_speed"])] * orbit_sign if orbiting else 0.0
	orbit_rate = lerpf(orbit_rate, orbit_goal, Smooth.blend(1.0 / ORBIT_RAMP * 2.0, delta))
	if absf(orbit_rate) > 0.01:
		var turn := deg_to_rad(orbit_rate) * delta
		var off := pose.pos - orbit_pivot
		pose.pos = orbit_pivot + Basis(Vector3.UP, turn) * off
		yaw_goal += turn
		pose.yaw += turn
	pose.pos += velocity * delta
	pose.pos.y = clampf(pose.pos.y, float(d.options["min_height"]), float(d.options["max_height"]))
	if orbiting:
		# Keep the pivot in the middle of the picture as the camera goes round.
		var look := Smooth.Pose.new()
		look.pos = pose.pos
		look.look_at_point(orbit_pivot)
		yaw_goal = look.yaw
		pitch_goal = look.pitch
	var t := Smooth.blend(LOOK_RATE, delta)
	pose.yaw = lerp_angle(pose.yaw, yaw_goal, t)
	pose.pitch = lerpf(pose.pitch, pitch_goal, t)
	pose.fov = lerpf(pose.fov, fov_goal, Smooth.blend(5.0, delta))
	return pose


## Mouse look (the mouse is captured), the wheel for the field of view, the camera keys.
func input(event: InputEvent) -> bool:
	var mm := event as InputEventMouseMotion
	if mm != null:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or orbiting:
			return false
		var k := LOOK_DEGREES_PER_PIXEL * float(d.options["mouse_sensitivity"])
		yaw_goal -= deg_to_rad(mm.relative.x * k)
		pitch_goal = clampf(pitch_goal - deg_to_rad(mm.relative.y * k), deg_to_rad(-89.0), deg_to_rad(89.0))
		return true
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			fov_goal = clampf(fov_goal - FOV_STEP, 10.0, 110.0)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fov_goal = clampf(fov_goal + FOV_STEP, 10.0, 110.0)
			return true
	var keys = d.api.keys
	if keys.pressed(event, "faster"):
		_step(1)
		return true
	if keys.pressed(event, "slower"):
		_step(-1)
		return true
	if keys.pressed(event, "orbit"):
		toggle_orbit()
		return true
	return false


## O: orbit the ground in the middle of the picture (or a point ahead when looking at the sky).
func toggle_orbit() -> void:
	if orbiting:
		orbiting = false
		d.api.ui.message("Orbit stopping")
		return
	var g = d.api.camera.center_ground()
	if g is Vector3 and (g as Vector3).distance_to(pose.pos) < 1500.0:
		orbit_pivot = g
	else:
		orbit_pivot = pose.pos + pose.forward() * 40.0
		orbit_pivot.y = 0.0
	orbiting = true
	d.api.ui.message("Orbit at %s°/s (+ and - change it, O again to stop)" % _num(ORBIT_SPEEDS[int(d.options["orbit_speed"])]))


func _step(dir: int) -> void:
	if orbiting:
		d.options["orbit_speed"] = clampi(int(d.options["orbit_speed"]) + dir, 0, ORBIT_SPEEDS.size() - 1)
		d.api.ui.message("Orbit speed %s°/s" % _num(ORBIT_SPEEDS[int(d.options["orbit_speed"])]))
	else:
		d.options["speed"] = clampi(int(d.options["speed"]) + dir, 0, SPEEDS.size() - 1)
		d.api.ui.message("Camera speed %s tiles/s" % _num(SPEEDS[int(d.options["speed"])]))
	d.options_changed()


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)
