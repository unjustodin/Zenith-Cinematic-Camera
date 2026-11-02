extends Node
## Zenith Cinematic Camera: free-flying shots, smooth camera moves, tracking shots, overhead
## timelapses, an idle mode and a recorder camera, for Zenith (Factorio in 3D). This is the entry script Zenith starts
## with its add-on API (see Zenith's docs/ADDONS.md). Everything here moves only the camera and
## changes what is shown: nothing it does changes the game.
##
## The director: registers the keys, takes the camera while a mode films and blends from one shot
## to the next, puts each frame's pose on the camera through shot.gd (height and tilt limits, field
## of view, depth of field, letterbox), and glides back to the player's own view at the end. The
## modes are in scripts/: free_camera, timelapse, tracking, moves, camera_path, idle, and the camera
## mode (camera_mode.gd's panel, rec_shot.gd's shot, rec_view.gd showing it, recorder.gd filming it).
## On Zenith's add-on API 1.1 the options are Zenith settings too (settings_table.gd), on the add-on's
## page of Zenith's Add-ons menu.

const Smooth := preload("scripts/smooth.gd")
const Shot := preload("scripts/shot.gd")
const FreeCamera := preload("scripts/free_camera.gd")
const Timelapse := preload("scripts/timelapse.gd")
const Tracking := preload("scripts/tracking.gd")
const Moves := preload("scripts/moves.gd")
const CameraPath := preload("scripts/camera_path.gd")
const Idle := preload("scripts/idle.gd")
const CameraPanel := preload("scripts/panel.gd")
const RecShot := preload("scripts/rec_shot.gd")
const RecView := preload("scripts/rec_view.gd")
const Recorder := preload("scripts/recorder.gd")
const CameraMode := preload("scripts/camera_mode.gd")
const SettingsTable := preload("scripts/settings_table.gd")

## Seconds the camera takes to glide back to the player's view.
const RETURN_TIME := 1.4

## Every option and its default (kept for all saves in the add-on's data).
const DEFAULTS := {
	"speed": 4,  # FreeCamera.SPEEDS index: 8 tiles a second
	"orbit_speed": 3,  # FreeCamera.ORBIT_SPEEDS index: 5 degrees a second
	"mouse_sensitivity": 1.0,
	"fov": 50.0,
	"dof": false,
	"dof_amount": 0.5,
	"letterbox": false,
	"min_height": 1.5,
	"max_height": 400.0,
	"max_tilt_down": 89.0,
	"max_tilt_up": 40.0,
	"glide_back": true,
	"placement": "behind",
	"move_kind": "orbit",
	"move_speed": 6.0,
	"move_length": 60.0,
	"move_loop": false,
	"path_speed": 8.0,
	"path_loop": false,
	"idle_after": 0.0,  # minutes without input before idle mode starts by itself; 0: never
	"idle_shot": 25.0,
	"timelapse_every": 5.0,
	"timelapse_height": 160.0,
	"timelapse_angle": "down",
	"timelapse_ortho": false,
	"timelapse_lighter": true,
	"timelapse_daytime": "run",
	"timelapse_clean": true,
	"timelapse_width": 1920,
	"frames_folder": "",
	# The camera mode and its recorder.
	"rec_follow": "player",  # or "spot"
	"rec_player": "",  # a player's name; "" yourself
	"rec_distance": 60.0,
	"rec_tilt": 45.0,
	"rec_spin": 3.0,
	"rec_combat": true,
	"rec_combat_distance": 28.0,
	"rec_combat_spin": 4.0,
	"rec_swaps": false,
	"rec_swap_every": 20.0,
	"rec_timelapse": false,
	"rec_every": 2.0,
	"rec_play_rate": 30,
	"rec_format": "avi",
	"rec_height": 1080,
	"rec_rate": 30,
	"rec_folder": "",
}

var api
var options := {}
var mode = null
var shot: Shot
var free_cam: FreeCamera
var timelapse: Timelapse
var tracking: Tracking
var moves: Moves
var path: CameraPath
var idle: Idle
var panel: CameraPanel
var rec_shot: RecShot
var rec_view: RecView
var recorder: Recorder
var camera_mode: CameraMode
## The timelapse hid the interface for its frames (and shows it again when it ends).
var hid_for_frames := false
## Saved paths of this save: name -> CameraPath.to_data().
var saved_paths := {}

var _blend_from: Smooth.Pose = null
var _blend_t := 0.0
var _blend_len := -1.0
var _returning := false
var _return_t := 0.0
var _last_pose := Smooth.Pose.new()
var _idle_clock := 0.0
var _save_in := -1.0
var _background_timelapse := false
var _rec_mark: HBoxContainer
var _rec_mark_label: Label
var _settings_on := false  # Zenith's add-on API 1.1: the options are Zenith settings too
var _settings_dirty := {}  # set while a slider moves, written to Zenith's settings file once it settles
## While recording with the camera view open, the screen shows the recorder's own picture and
## Zenith's main view draws no 3D: the world isn't drawn twice (the main 3D view as it was, to restore).
var _screen_layer: CanvasLayer
var _main_3d_was_disabled := false


func addon_start(a) -> void:
	api = a
	options = DEFAULTS.duplicate(true)
	var saved: Dictionary = api.storage.read_global("options")
	for k in saved:
		if options.has(k):
			# JSON gives numbers back as floats: whole-number options stay ints (list indices, widths).
			options[k] = int(saved[k]) if DEFAULTS[k] is int else saved[k]
	api.keys.add("free_camera", "Free camera on/off (also ends any shot)", [KEY_F8])
	api.keys.add("window", "Camera window", [KEY_F8 | KEY_MASK_SHIFT])
	api.keys.add("hide_interface", "Hide the interface and the cursor", [KEY_F11])
	api.keys.add("idle", "Idle mode on/off", [KEY_F8 | KEY_MASK_CTRL])
	api.keys.add("camera_mode", "Camera mode (the recorder's view and its panel) on/off", [KEY_F8 | KEY_MASK_ALT])
	api.keys.add("record", "Start / stop recording", [KEY_F8 | KEY_MASK_CTRL | KEY_MASK_SHIFT])
	for k in [["forward", "Fly forward", [KEY_W, KEY_UP]], ["back", "Fly back", [KEY_S, KEY_DOWN]],
			["left", "Fly left", [KEY_A, KEY_LEFT]], ["right", "Fly right", [KEY_D, KEY_RIGHT]],
			["up", "Fly up", [KEY_E, KEY_SPACE]], ["down", "Fly down", [KEY_Q, KEY_CTRL]],
			["faster", "Faster (orbiting: orbit faster)", [KEY_EQUAL, KEY_KP_ADD]],
			["slower", "Slower (orbiting: orbit slower)", [KEY_MINUS, KEY_KP_SUBTRACT]],
			["orbit", "Orbit the middle of the screen", [KEY_O]],
			["track", "Follow what moves in the middle of the screen", [KEY_T]],
			["next", "Follow the next one of the same kind", [KEY_N]],
			["placement", "Follow from behind, beside, above, a fixed spot, riding along", [KEY_V]],
			["add_point", "Add a path point here", [KEY_K]],
			["play_path", "Play the path / stop it", [KEY_P]],
			["letterbox", "Letterbox bars on/off", [KEY_B]]]:
		api.keys.add(k[0], k[1], k[2], "camera")
	shot = Shot.new(self)
	free_cam = FreeCamera.new(self)
	timelapse = Timelapse.new(self)
	tracking = Tracking.new(self)
	tracking.placement = str(options["placement"])
	moves = Moves.new(self)
	path = CameraPath.new(self)
	idle = Idle.new(self, tracking, moves)
	panel = CameraPanel.new(self)
	rec_shot = RecShot.new(self)
	rec_view = RecView.new(self)
	recorder = Recorder.new(self)
	camera_mode = CameraMode.new(self)
	_declare_settings()
	api.camera.lost.connect(_on_lost)
	api.game_started.connect(_on_game_started)
	api.game_ended.connect(_on_game_ended)
	api.ui.set_options(panel.build_options)
	if api.in_game():
		_on_game_started()


func addon_stop() -> void:
	_end_everything()
	_save_options()


## On Zenith's add-on API 1.1 every option is a Zenith setting as well, shown with the keys on the
## add-on's page of the Add-ons menu. Values kept by an older version (options.json) move over once.
func _declare_settings() -> void:
	_settings_on = api.get("level") != null and float(api.level) >= 1.1 and api.get("settings") != null
	if not _settings_on:
		return
	for e in SettingsTable.entries():
		var key: String = e[0]
		var legacy = options[key]
		var v = api.settings.add(key, e[1], DEFAULTS[key], e[2], e[3])
		if api.settings.is_default(key) and str(legacy) != str(DEFAULTS[key]):
			api.settings.set_value(key, legacy)
			v = api.settings.value(key)
		options[key] = v
	api.settings.changed.connect(_on_setting_changed)


## Changed in Zenith's Add-ons menu.
func _on_setting_changed(key: String, v) -> void:
	if not options.has(key) or str(options[key]) == str(v):
		return
	options[key] = v
	if key == "placement":
		tracking.placement = str(v)
	_save_in = 0.8
	panel.refresh()
	camera_mode.rebuild()


# --- shots --------------------------------------------------------------------------------------

## Films with a mode, blending from what is on screen now. False (with a message) when Zenith
## can't give the camera now (no game, a ride to a platform).
func begin(m) -> bool:
	var from := current_pose()
	if mode != null and mode != m:
		mode.stop()
		mode = null
	if not api.camera.has() or api.camera.has_input() != bool(m.takes_input):
		if not api.camera.take({"input": bool(m.takes_input)}):
			api.ui.message("The camera isn't free now")
			return false
	_returning = false
	shot.reset()
	api.camera.set_focus(null)  # the world loads round the new shot (a mode may name its own point)
	mode = m
	m.start(from)
	_blend_from = from
	_blend_t = 0.0
	_blend_len = -1.0
	panel.refresh()
	return true


## Ends the shot: back to the player's own view (gliding there, if set).
func stop(glide := true) -> void:
	if mode != null:
		var m = mode
		mode = null
		m.stop()
	if not api.camera.has():
		panel.refresh()
		return
	if glide and bool(options["glide_back"]):
		_returning = true
		_return_t = 0.0
		_blend_from = current_pose()
		api.camera.capture_mouse(false)
	else:
		_release()
	panel.refresh()


func _release() -> void:
	_returning = false
	api.camera.release()
	shot.reset()
	panel.refresh()


## What the camera shows now: the last pose put on it while the add-on has it, else the player's.
func current_pose() -> Smooth.Pose:
	if api.camera.has():
		return _last_pose.copy()
	var p := Smooth.pose_from(api.camera.transform(), api.camera.fov())
	return p


func filming() -> bool:
	return mode != null or _returning


func start_free() -> void:
	if begin(free_cam):
		api.ui.message("Free camera: WASD, Q/E, mouse look · + and - speed · O orbit · %s back" % api.keys.text("free_camera"))


func start_tracking(what := "") -> void:
	tracking.announce = true
	var ok: bool = tracking.track_any() if what == "" else tracking.track_nearest(what)
	if ok:
		tracking.placement = str(options["placement"])
		begin(tracking)
		api.ui.message("%s · N next · V placement" % tracking.label())


func start_move(kind := "") -> void:
	moves.kind = kind if kind != "" else str(options["move_kind"])
	begin(moves)


func play_path() -> void:
	if not path.can_play():
		api.ui.message("Add at least two points first (%s adds one where the camera is)" % api.keys.text("add_point"))
		return
	begin(path)


func add_path_point() -> void:
	path.add_point(current_pose())
	save_paths()
	api.ui.message("Point %d added to \"%s\" (%s plays the path)" % [path.points.size(), path.name, api.keys.text("play_path")])
	panel.refresh()


func start_idle(automatic := false) -> void:
	idle.automatic = automatic
	if begin(idle):
		if not automatic:
			api.ui.message("Idle mode: %s ends it" % api.keys.text("idle"))


## Overhead timelapse on screen (you play on through it) or in the background (your camera stays).
func start_timelapse(background: bool) -> void:
	stop_timelapse()
	if background:
		timelapse.begin(true)
		_background_timelapse = true
	else:
		timelapse.begin(false)
		if not begin(timelapse):
			timelapse.end()
	panel.refresh()


func stop_timelapse() -> void:
	if _background_timelapse:
		_background_timelapse = false
		timelapse.end()
	elif mode == timelapse:
		stop()
	panel.refresh()


func timelapse_running() -> bool:
	return timelapse.running


# --- the camera mode and the recorder ----------------------------------------------------------

## The camera mode: its panel on the left and Zenith's camera on its shot (the camera view).
func open_camera_mode() -> void:
	if not api.in_game():
		return
	if mode != rec_view:
		rec_shot.reset()
		rec_shot.update(0.0)
		if not begin(rec_view):
			return
	camera_mode.open()


## Your own camera back (gliding there); a recording goes on in the background.
func close_camera_mode() -> void:
	camera_mode.close()
	if mode == rec_view:
		stop()
	if recorder.recording:
		api.ui.message("Recording on in the background (%s stops it)" % api.keys.text("record"))


func camera_mode_open() -> bool:
	return mode == rec_view


func toggle_recording() -> void:
	if recorder.recording:
		recorder.stop()
	else:
		if not camera_mode_open():
			rec_shot.reset()
		rec_shot.update(0.0)
		recorder.start()
	_show_rec_mark(recorder.recording)
	camera_mode.rebuild()


func open_recordings() -> void:
	var path := ProjectSettings.globalize_path(recorder.folder if recorder.folder != "" else recorder.root_folder())
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


## The red dot, the time and a Stop button, top middle, while recording (on the add-on's layer: it
## stays when the interface is hidden, and isn't in the recording).
func _show_rec_mark(on: bool) -> void:
	if on and _rec_mark == null:
		_rec_mark = HBoxContainer.new()
		_rec_mark.name = "RecordingMark"
		_rec_mark.add_theme_constant_override("separation", api.ui.kit.px(8))
		_rec_mark_label = Label.new()
		_rec_mark_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
		_rec_mark_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_rec_mark_label.add_theme_constant_override("outline_size", 4)
		_rec_mark_label.add_theme_font_size_override("font_size", api.ui.kit.px(18))
		_rec_mark_label.text = recorder.label()
		_rec_mark.add_child(_rec_mark_label)
		var stop_button: Button = api.ui.button("Stop", func() -> void: toggle_recording())
		stop_button.name = "StopRecording"
		stop_button.custom_minimum_size.x = api.ui.kit.px(64)
		stop_button.tooltip_text = "Stop recording (%s)" % api.keys.text("record")
		_rec_mark.add_child(stop_button)
		var holder := Control.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.name = "RecordingMarkHolder"
		holder.add_child(_rec_mark)
		_rec_mark.theme = api.ui.menu_kit.theme()
		api.ui.layer().add_child(holder)
	elif not on and _rec_mark != null:
		_rec_mark.get_parent().queue_free()
		_rec_mark = null
		_rec_mark_label = null


func _update_rec_mark() -> void:
	if _rec_mark == null:
		return
	_rec_mark_label.text = recorder.label()
	var screen: Vector2 = api.view.screen_size()
	_rec_mark.reset_size()
	_rec_mark.position = Vector2((screen.x - _rec_mark.size.x) * 0.5, api.ui.kit.px(8))


func toggle_interface() -> void:
	var hiding: bool = not api.view.interface_hidden()
	hid_for_frames = false
	api.view.hide_interface(hiding)
	if not hiding:
		api.ui.message("Interface back (%s hides it)" % api.keys.text("hide_interface"))


# --- each frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _save_in >= 0.0:
		_save_in -= delta
		if _save_in < 0.0:
			_save_options()
	if not api.in_game():
		return
	panel.tick(delta)
	camera_mode.tick(delta)
	if mode == rec_view and not camera_mode.is_open():
		close_camera_mode()  # its panel closed (Ã—, Esc)
	if mode == rec_view or recorder.recording:
		recorder.tick(delta, rec_shot.update(delta))
		_update_rec_mark()
	_show_recorder_on_screen(mode == rec_view and recorder.recording and not bool(options["rec_timelapse"]))
	shot.update_bars(delta, api.camera.has())
	if _background_timelapse:
		timelapse.tick(delta)
	_count_idle(delta)
	if _returning:
		_return_t += delta
		var goal := Smooth.pose_from(api.camera.player_view(), api.camera.player_fov())
		var p := Smooth.mix(_blend_from, goal, Smooth.ease_in_out(_return_t / RETURN_TIME))
		_last_pose = p
		shot.apply(p, delta)
		if _return_t >= RETURN_TIME:
			_release()
		return
	if mode == null or not api.camera.has():
		return
	var pose: Smooth.Pose = mode.update(delta)
	if pose == null:
		stop()
		return
	if _blend_from != null:
		if _blend_len < 0.0:
			# Longer blends for longer jumps: a swoop across the base, not a cut.
			_blend_len = clampf(0.8 + _blend_from.pos.distance_to(pose.pos) / 90.0, 0.8, 4.5)
		_blend_t += delta
		pose = Smooth.mix(_blend_from, pose, Smooth.ease_in_out(_blend_t / _blend_len))
		if _blend_t >= _blend_len:
			_blend_from = null
	# The timelapse's height is its own setting, above the shot limits if asked.
	var limit: bool = mode != timelapse
	_last_pose = shot.limited(pose) if limit else pose.copy()
	shot.apply(pose, delta, mode.focus_point() if mode != null else null, limit)


## Idle mode by itself after a while without input (if set), out of it at the first input.
func _count_idle(delta: float) -> void:
	var after := float(options["idle_after"])
	if after <= 0.0 or filming() or _background_timelapse or api.ui.menu_open():
		_idle_clock = 0.0
		return
	_idle_clock += delta
	if _idle_clock >= after * 60.0:
		_idle_clock = 0.0
		start_idle(true)


# --- input --------------------------------------------------------------------------------------

## Before Zenith's UI: mouse look while the mouse is captured, and any input ends an idle mode that
## started by itself.
func _input(event: InputEvent) -> void:
	var touched := event is InputEventKey or event is InputEventMouseButton \
		or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0)
	if touched:
		_idle_clock = 0.0
		if mode == idle and idle.automatic and (event.is_pressed() or event is InputEventMouseMotion):
			stop()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and mode != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mode.input(event):
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	var keys = api.keys
	if keys.pressed(event, "free_camera"):
		if filming():
			stop()
		else:
			start_free()
	elif keys.pressed(event, "window"):
		panel.toggle()
	elif keys.pressed(event, "hide_interface"):
		toggle_interface()
	elif keys.pressed(event, "camera_mode"):
		if camera_mode_open():
			close_camera_mode()
		else:
			open_camera_mode()
	elif keys.pressed(event, "record"):
		toggle_recording()
	elif keys.pressed(event, "idle"):
		if mode == idle:
			stop()
		else:
			start_idle(false)
	elif mode != null and mode.input(event):
		pass
	elif keys.pressed(event, "track"):
		start_tracking()
	elif keys.pressed(event, "add_point"):
		add_path_point()
	elif keys.pressed(event, "play_path"):
		if mode == path:
			begin(free_cam)
		else:
			play_path()
	elif keys.pressed(event, "letterbox"):
		options["letterbox"] = not bool(options["letterbox"])
		options_changed()
	else:
		return
	get_viewport().set_input_as_handled()


# --- the game and saving ------------------------------------------------------------------------

func _on_lost() -> void:
	if mode != null:
		var m = mode
		mode = null
		m.stop()
	_returning = false
	panel.refresh()


func _on_game_started() -> void:
	var data: Dictionary = api.storage.read("paths")
	saved_paths = data.get("paths", {}) if data.get("paths") is Dictionary else {}
	var current := str(data.get("current", ""))
	path = CameraPath.new(self)
	if saved_paths.has(current):
		path.from_data(saved_paths[current])
	_idle_clock = 0.0


func _on_game_ended() -> void:
	_end_everything()


## On: Zenith's main viewport stops drawing 3D and a full-screen picture of the recorder's view
## takes its place, under every window (the recorder draws a frame each 1/rate seconds, so the screen
## shows exactly what is filmed, at its rate). Off: the main view as it was. A timelapse keeps the
## main view (its frames are seconds apart).
func _show_recorder_on_screen(on: bool) -> void:
	var tex: Texture2D = recorder.texture() if on else null
	if tex != null and _screen_layer == null:
		_screen_layer = CanvasLayer.new()
		_screen_layer.name = "RecorderOnScreen"
		_screen_layer.layer = -100  # under Zenith's HUD and the add-ons' windows
		var rect := TextureRect.new()
		rect.name = "Picture"
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		_screen_layer.add_child(rect)
		add_child(_screen_layer)
		var vp := get_viewport()
		_main_3d_was_disabled = vp.disable_3d
		vp.disable_3d = true
	elif tex == null and _screen_layer != null:
		get_viewport().disable_3d = _main_3d_was_disabled
		_screen_layer.queue_free()
		_screen_layer = null


func _end_everything() -> void:
	_show_recorder_on_screen(false)
	if recorder.recording:
		recorder.stop()
	_show_rec_mark(false)
	camera_mode.close()
	if _background_timelapse or timelapse.running:
		_background_timelapse = false
		timelapse.end()
	if mode != null:
		var m = mode
		mode = null
		m.stop()
	_returning = false
	if api.camera.has():
		api.camera.release()
	if api.view.interface_hidden():
		api.view.hide_interface(false)
	panel.close()


func options_changed() -> void:
	_save_in = 0.8  # once things settle (a slider dragged saves once)
	panel.refresh()
	if _settings_on:
		for e in SettingsTable.entries():
			var key: String = e[0]
			if str(api.settings.value(key)) != str(options[key]):
				api.settings.set_value(key, options[key], false)
				_settings_dirty[key] = true


func _save_options() -> void:
	if api != null:
		api.storage.write_global(options, "options")
		# Zenith's settings file, written once a slider has settled.
		for key in _settings_dirty:
			api.settings.set_value(key, options[key])
		_settings_dirty.clear()


## Keeps this save's paths: the one being edited, under its name.
func save_paths() -> void:
	if path.points.is_empty():
		saved_paths.erase(path.name)
	else:
		saved_paths[path.name] = path.to_data()
	api.storage.write({"current": path.name, "paths": saved_paths}, "paths")


func load_path(path_name: String) -> void:
	if saved_paths.has(path_name):
		path.from_data(saved_paths[path_name])
		save_paths()


func new_path(path_name: String) -> void:
	path.name = path_name.strip_edges() if path_name.strip_edges() != "" else "Path %d" % (saved_paths.size() + 1)
	path.clear()
	save_paths()
