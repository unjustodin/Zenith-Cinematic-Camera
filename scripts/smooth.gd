extends RefCounted
## Smoothing for every move the camera makes: easing, damping, a critically damped spring, ramped
## speeds (no instant starts or stops), and the Pose the modes hand to the director.


## Where the camera is and where it looks: yaw turns about the vertical (0 looks north, positive
## turns left, towards west), pitch tilts (negative looks down), both in radians; fov in degrees
## (0: the add-on's setting); ortho > 0 is an orthographic camera that many tiles high.
class Pose:
	var pos := Vector3.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var fov := 0.0
	var ortho := 0.0

	func copy() -> Pose:
		var p := Pose.new()
		p.pos = pos
		p.yaw = yaw
		p.pitch = pitch
		p.fov = fov
		p.ortho = ortho
		return p

	func basis() -> Basis:
		return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

	func transform() -> Transform3D:
		return Transform3D(basis(), pos)

	## The way it looks (unit vector).
	func forward() -> Vector3:
		return -basis().z

	## Turns it to look at a point.
	func look_at_point(at: Vector3) -> void:
		var d := at - pos
		if d.length() < 0.001:
			return
		d = d.normalized()
		yaw = atan2(-d.x, -d.z)
		pitch = asin(clampf(d.y, -1.0, 1.0))


static func pose_from(t: Transform3D, fov := 0.0) -> Pose:
	var p := Pose.new()
	p.pos = t.origin
	var e := t.basis.orthonormalized().get_euler()  # YXZ: x pitch, y yaw
	p.pitch = e.x
	p.yaw = e.y
	p.fov = fov
	return p


## a and b mixed by t (0 a, 1 b): positions straight, angles the short way round.
static func mix(a: Pose, b: Pose, t: float) -> Pose:
	var p := Pose.new()
	p.pos = a.pos.lerp(b.pos, t)
	p.yaw = lerp_angle(a.yaw, b.yaw, t)
	p.pitch = lerpf(a.pitch, b.pitch, t)
	var fa := a.fov if a.fov > 0.0 else b.fov
	var fb := b.fov if b.fov > 0.0 else a.fov
	p.fov = lerpf(fa, fb, t)
	p.ortho = b.ortho if t >= 0.5 else a.ortho
	return p


## Exponential approach: the share of the way to go covered this frame, frame-rate independent.
static func blend(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## Slow at both ends, 0 -> 0, 1 -> 1 (smootherstep: no jolt at either end).
static func ease_in_out(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## Distance covered after `t` seconds by something that speeds up smoothly from rest to `speed`
## over `ramp` seconds and then keeps going.
static func ramp_distance(t: float, speed: float, ramp: float) -> float:
	if t <= 0.0:
		return 0.0
	if ramp <= 0.0:
		return speed * t
	if t < ramp:
		var x := t / ramp
		return speed * ramp * (x * x * x - x * x * x * x * 0.5)
	return speed * (ramp * 0.5 + (t - ramp))


## A move of `length` at `speed` that starts and stops smoothly: [distance at time t, its whole
## duration]. Short moves ramp over less time.
static func ramped_move(t: float, length: float, speed: float, ramp: float) -> Array:
	speed = maxf(speed, 0.001)
	ramp = minf(ramp, length / speed)
	var total := length / speed + ramp
	if t >= total:
		return [length, total]
	if t <= total * 0.5:
		return [ramp_distance(t, speed, ramp), total]
	return [length - ramp_distance(total - t, speed, ramp), total]


## A critically damped spring: follows a moving goal smoothly, never overshooting.
class Spring:
	var value := Vector3.ZERO
	var velocity := Vector3.ZERO
	var started := false

	func reset(v: Vector3) -> void:
		value = v
		velocity = Vector3.ZERO
		started = true

	## `omega` is its stiffness (about 4 / the seconds it takes to catch up).
	func update(goal: Vector3, omega: float, delta: float) -> Vector3:
		if not started:
			reset(goal)
			return value
		var f := 1.0 + 2.0 * delta * omega
		var oo := omega * omega
		var hoo := delta * oo
		var hhoo := delta * hoo
		var det := 1.0 / (f + hhoo)
		var x := (value * f + velocity * delta + goal * hhoo) * det
		var v := (velocity + (goal - value) * hoo) * det
		value = x
		velocity = v
		return value
