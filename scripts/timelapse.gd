extends RefCounted
## The overhead timelapse: a fixed camera high over an area, looking straight down or at
## Factorio's angle, left running while you play. Every N seconds it saves a frame (numbered PNGs,
## ready to join into a video), and while it runs it can ask Zenith for lighter updates and hold
## the time of day.
##
## Two ways to run it:
##   on screen      the camera itself goes up there; you keep playing through it (your controls
##                  stay on), and the frames are the window (the interface hidden while capturing)
##   in background  your own camera stays with you; a second camera draws the area off screen once
##                  per frame saved. The area must be within the chunks Zenith draws round you.

const Smooth := preload("smooth.gd")

const ANGLES := {"down": "Straight down", "factorio": "Factorio's angle"}
const FACTORIO_PITCH := 48.0

var d  # the director
var takes_input := false  # you play on while it runs
var background := false
var center := Vector3.ZERO
var frames := 0
var folder := ""
var running := false

var _pose := Smooth.Pose.new()
var _timer := 0.0
var _viewport: SubViewport
var _camera: Camera3D
var _capturing := false
var _mark: Label


func _init(director) -> void:
	d = director


func label() -> String:
	var every := float(d.options["timelapse_every"])
	var saving := (", a frame every %ss, %d saved" % [_num(every), frames]) if every > 0.0 else ""
	return "Timelapse %s%s" % ["in the background" if background else "overhead", saving]


## The camera's pose for the shot over `center`.
func shot_pose() -> Smooth.Pose:
	var h := float(d.options["timelapse_height"])
	var p := Smooth.Pose.new()
	if str(d.options["timelapse_angle"]) == "down":
		p.pos = center + Vector3.UP * h
		p.yaw = 0.0
		p.pitch = deg_to_rad(-89.5)  # not quite straight down: "forward" for walking stays north
	else:
		var pitch := deg_to_rad(FACTORIO_PITCH)
		p.pos = center + Vector3(0.0, h, h / tan(pitch))
		p.yaw = 0.0
		p.pitch = -pitch
	if bool(d.options["timelapse_ortho"]):
		p.ortho = h * 1.1
	return p


## Starts it over the ground in the middle of the picture (or `at`).
func begin(in_background: bool, at = null) -> void:
	background = in_background
	if at is Vector3:
		center = at
	else:
		var g = d.api.camera.center_ground()
		var f: Vector2 = d.api.world.focus()
		center = g if g is Vector3 and (g as Vector3).distance_to(Vector3(f.x, 0.0, f.y)) < 400.0 else Vector3(f.x, 0.0, f.y)
	center.y = 0.0
	frames = 0
	_timer = 0.0
	folder = _new_folder()
	running = true
	_lighter(true)
	var held := str(d.options["timelapse_daytime"])
	if held != "run":
		d.api.view.hold_daytime(float(held))
	if background:
		_make_viewport()
		d.api.ui.message("Timelapse in the background: a frame every %ss to %s" % [_num(float(d.options["timelapse_every"])), ProjectSettings.globalize_path(folder)])
		_show_mark(true)
	else:
		d.api.ui.message("Timelapse overhead: frames to %s" % ProjectSettings.globalize_path(folder))


## Ends it: lighter updates and the held time of day are given back.
func end() -> void:
	if not running:
		return
	running = false
	_lighter(false)
	if d.api.view.daytime_held():
		d.api.view.hold_daytime(-1.0)
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
		_camera = null
	_show_mark(false)
	if d.hid_for_frames:
		d.hid_for_frames = false
		d.api.view.hide_interface(false)
	if frames > 0:
		d.api.ui.message("Timelapse: %d frames in %s" % [frames, ProjectSettings.globalize_path(folder)])


# --- as a camera mode (on screen) ---------------------------------------------------------------

func start(_from: Smooth.Pose) -> void:
	d.api.camera.set_focus(Vector2(center.x, center.z))


func stop() -> void:
	end()


func focus_point():
	return center


func update(delta: float) -> Smooth.Pose:
	_pose = shot_pose()
	tick(delta)
	return _pose


func input(_event: InputEvent) -> bool:
	return false


## Each frame while it runs (on screen or not): a frame saved every N seconds.
func tick(delta: float) -> void:
	if not running:
		return
	var every := float(d.options["timelapse_every"])
	if every <= 0.0 or _capturing:
		return
	_timer += delta
	if _timer < every:
		return
	_timer = fmod(_timer, every)
	if background:
		_capture_background()
	else:
		_capture_screen()


func _capture_screen() -> void:
	# The first frame of an on-screen timelapse hides the interface (the HUD would be in the frames).
	if bool(d.options["timelapse_clean"]) and not d.api.view.interface_hidden():
		d.hid_for_frames = true
		d.api.view.hide_interface(true)
		_timer = float(d.options["timelapse_every"]) - 0.2  # saved once the interface is gone
		return
	if d.api.view.save_frame(_frame_path()):
		frames += 1


func _capture_background() -> void:
	if _viewport == null:
		_make_viewport()
	var p := shot_pose()
	_camera.global_transform = p.transform()
	if p.ortho > 0.0:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = p.ortho
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = float(d.options["fov"])
	_capturing = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if _viewport != null and d.api.view.save_frame(_frame_path(), _viewport):
		frames += 1
	_capturing = false
	if _mark != null:
		_mark.text = "● Timelapse %d" % frames


func _make_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "TimelapseView"
	var size: Vector2 = d.api.view.screen_size()
	var w := int(d.options["timelapse_width"])
	_viewport.size = Vector2i(w, roundi(w * size.y / maxf(size.x, 1.0))) if w > 0 else Vector2i(size)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.world_3d = d.api.view.world_3d()
	_viewport.msaa_3d = Viewport.MSAA_2X
	_camera = Camera3D.new()
	_camera.far = 3000.0
	_viewport.add_child(_camera)
	_camera.current = true
	d.add_child(_viewport)


func _show_mark(on: bool) -> void:
	if on and _mark == null:
		_mark = Label.new()
		_mark.text = "● Timelapse 0"
		_mark.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		_mark.add_theme_color_override("font_outline_color", Color.BLACK)
		_mark.add_theme_constant_override("outline_size", 4)
		_mark.position = Vector2(16, 12)
		_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.api.ui.layer().add_child(_mark)
	elif not on and _mark != null:
		_mark.queue_free()
		_mark = null


func _lighter(on: bool) -> void:
	if on and bool(d.options["timelapse_lighter"]):
		# From high above belt items, hands and far-off movers aren't seen: the bridge sends them
		# less often and nearer, which the game feels most (Zenith's UPS governor may hold back more).
		d.api.updates.request({"rate": 2, "near": 8, "entity": 128})
	else:
		d.api.updates.clear()


func _new_folder() -> String:
	var root := str(d.options["frames_folder"])
	if root == "":
		root = d.api.storage.folder().path_join("frames")
	var save: String = d.api.storage.save_key()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	return root.path_join(save if save != "" else "game").path_join(stamp)


func _frame_path() -> String:
	return folder.path_join("frame_%05d.png" % (frames + 1))


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)
