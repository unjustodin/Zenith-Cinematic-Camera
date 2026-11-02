extends RefCounted
## Clean shots: puts each frame's pose on Zenith's camera inside the limits (height above the
## ground, how far it tilts), with the field of view, depth of field focused on what is filmed, and
## letterbox bars for a film look.

const Smooth := preload("smooth.gd")

## Film's 2.39:1 frame.
const LETTERBOX := 2.39

var d  # the director (main.gd)
var _attrs := CameraAttributesPractical.new()
var _focus_distance := -1.0
var _fov := -1.0
var _bars: Array[ColorRect] = []
var _bars_shown := 0.0


func _init(director) -> void:
	d = director


## The pose kept within the height and tilt limits.
func limited(p: Smooth.Pose) -> Smooth.Pose:
	var out := p.copy()
	out.pos.y = clampf(out.pos.y, float(d.options["min_height"]), float(d.options["max_height"]))
	out.pitch = clampf(out.pitch, deg_to_rad(-float(d.options["max_tilt_down"])), deg_to_rad(float(d.options["max_tilt_up"])))
	return out


## Puts a pose on the camera. `focus`: the point filmed (Vector3) for the depth of field, or null
## for the ground in the middle of the picture.
func apply(pose: Smooth.Pose, delta: float, focus = null, limit := true) -> void:
	var cam: Camera3D = d.api.camera.node()
	if cam == null:
		return
	var p := limited(pose) if limit else pose.copy()
	d.api.camera.set_transform(p.transform())
	var want := p.fov if p.fov > 0.0 else float(d.options["fov"])
	_fov = want if _fov < 0.0 else lerpf(_fov, want, Smooth.blend(6.0, delta))
	if p.ortho > 0.0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = p.ortho
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = _fov
	cam.far = maxf(cam.far, 2000.0)
	_depth_of_field(cam, p, focus, delta)


func reset() -> void:
	_focus_distance = -1.0
	_fov = -1.0


func _depth_of_field(cam: Camera3D, p: Smooth.Pose, focus, delta: float) -> void:
	if not bool(d.options["dof"]) or p.ortho > 0.0:
		if cam.attributes == _attrs:
			cam.attributes = null
		return
	var distance := 40.0
	if focus is Vector3:
		distance = p.pos.distance_to(focus)
	else:
		var g = d.api.camera.center_ground()
		if g is Vector3:
			distance = p.pos.distance_to(g)
	distance = clampf(distance, 2.0, 600.0)
	_focus_distance = distance if _focus_distance < 0.0 else lerpf(_focus_distance, distance, Smooth.blend(3.0, delta))
	var f := _focus_distance
	var amount := float(d.options["dof_amount"])
	_attrs.dof_blur_far_enabled = true
	_attrs.dof_blur_far_distance = f * 1.15 + 2.0
	_attrs.dof_blur_far_transition = f * 0.9 + 6.0
	_attrs.dof_blur_near_enabled = true
	_attrs.dof_blur_near_distance = maxf(0.3, f * 0.55)
	_attrs.dof_blur_near_transition = maxf(0.3, f * 0.35)
	_attrs.dof_blur_amount = clampf(amount, 0.0, 1.0) * 0.2
	cam.attributes = _attrs


## Letterbox bars slide in while filming with them on, and out otherwise.
func update_bars(delta: float, filming: bool) -> void:
	var want := 1.0 if filming and bool(d.options["letterbox"]) else 0.0
	_bars_shown = move_toward(_bars_shown, want, delta * 1.5)
	if _bars.is_empty() and _bars_shown <= 0.0:
		return
	if _bars.is_empty():
		var layer: CanvasLayer = d.api.ui.layer()
		for i in 2:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(bar)
			_bars.append(bar)
	var screen: Vector2 = d.api.view.screen_size()
	var full := maxf(0.0, (screen.y - screen.x / LETTERBOX) * 0.5)
	var h := full * Smooth.ease_in_out(_bars_shown)
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(screen.x, h)
	_bars[1].position = Vector2(0.0, screen.y - h)
	_bars[1].size = Vector2(screen.x, h)
	for b in _bars:
		b.visible = h > 0.5


func free_bars() -> void:
	for b in _bars:
		if is_instance_valid(b):
			b.queue_free()
	_bars.clear()
	_bars_shown = 0.0
