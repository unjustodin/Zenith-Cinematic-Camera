extends RefCounted
## The camera window (Shift+F8 by default), in Zenith's own style: what is filming now, and a tab
## per kind of shot with its options. Options are saved for every save; paths with the save.

const FreeCamera := preload("free_camera.gd")
const Moves := preload("moves.gd")

const TABS := ["Camera", "Timelapse", "Follow", "Moves", "Path", "Idle", "Shot"]
const DAYTIMES := [["Let it run", "run"], ["Hold at noon", "0.0"], ["Hold at evening", "0.2"],
	["Hold at night", "0.5"], ["Hold at morning", "0.8"]]
const WIDTHS := [["The window's size", 0], ["1280 wide", 1280], ["1920 wide", 1920], ["2560 wide", 2560], ["3840 wide", 3840]]

var d  # the director
var _win := {}
var _tab := "Camera"
var _tabs: Array[Button] = []
var _content: VBoxContainer
var _status: Label
var _live: Array = []  # [Label, Callable returning its text]
var _clock := 0.0


func _init(director) -> void:
	d = director


func toggle() -> void:
	_ensure()
	d.api.ui.toggle(_win["frame"])
	refresh()


func close() -> void:
	if not _win.is_empty():
		d.api.ui.show(_win["frame"], false)


func is_open() -> bool:
	return not _win.is_empty() and d.api.ui.is_open(_win["frame"])


## The status line and the window's live numbers, now.
func refresh() -> void:
	if not is_open():
		return
	_status.text = _status_text()
	for pair in _live:
		if is_instance_valid(pair[0]):
			(pair[0] as Label).text = (pair[1] as Callable).call()


func tick(delta: float) -> void:
	_clock += delta
	if _clock >= 0.5:
		_clock = 0.0
		refresh()


func _status_text() -> String:
	var parts: Array = []
	if d.mode != null:
		parts.append(d.mode.label())
	elif d.filming():
		parts.append("Gliding back")
	else:
		parts.append("Your own camera")
	if d.timelapse_running() and d.mode != d.timelapse:
		parts.append(d.timelapse.label())
	return " · ".join(parts)


func _ensure() -> void:
	if not _win.is_empty():
		return
	var ui = d.api.ui
	_win = ui.window("Cinematic camera")
	var box: VBoxContainer = _win["box"]
	_status = ui.label("")
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	box.add_child(row)
	for t in TABS:
		var b := Button.new()
		b.text = t
		b.theme_type_variation = "FTab"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(ui.kit.px(64), ui.kit.px(30))
		var tab: String = t
		b.pressed.connect(func() -> void: _open(tab))
		row.add_child(b)
		_tabs.append(b)
	var pane: PanelContainer = ui.kit.panel("FShallowFrame")
	pane.custom_minimum_size = Vector2(ui.kit.px(520), ui.kit.px(330))
	box.add_child(pane)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, ui.kit.px(10))
	pane.add_child(pad)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", ui.kit.px(6))
	pad.add_child(_content)
	_open(_tab)


func _open(tab: String) -> void:
	_tab = tab
	for b in _tabs:
		b.button_pressed = b.text == tab
	for c in _content.get_children():
		c.queue_free()
	_live.clear()
	match tab:
		"Camera": _camera_tab()
		"Timelapse": _timelapse_tab()
		"Follow": _follow_tab()
		"Moves": _moves_tab()
		"Path": _path_tab()
		"Idle": _idle_tab()
		"Shot": _shot_tab()
	refresh()


# --- tabs ---------------------------------------------------------------------------------------

func _camera_tab() -> void:
	var ui = d.api.ui
	_buttons([["Free camera", Callable(d, "start_free")], ["Orbit here", _orbit_here], ["Back to my camera", func() -> void: d.stop()]])
	_add(ui.row("Speed", _index_slider("speed", FreeCamera.SPEEDS, " tiles/s")))
	_add(ui.row("Orbit speed", _index_slider("orbit_speed", FreeCamera.ORBIT_SPEEDS, "°/s")))
	_add(ui.row("Mouse look", _slider("mouse_sensitivity", 0.2, 3.0, 0.05, "%s×")))
	_add(_check("Glide back to my camera at the end", "glide_back"))
	_add(ui.note("%s: free camera on and off (it also ends any shot). In the camera: %s to fly, %s up, %s down, the mouse to look, the wheel to zoom, %s and %s for the speed, %s to orbit, %s to follow what's in the middle. %s hides the interface; %s starts idle mode." % [
		d.api.keys.text("free_camera"), "WASD", d.api.keys.text("up"), d.api.keys.text("down"), d.api.keys.text("faster"),
		d.api.keys.text("slower"), d.api.keys.text("orbit"), d.api.keys.text("track"), d.api.keys.text("hide_interface"),
		d.api.keys.text("idle")], 500))


func _timelapse_tab() -> void:
	var ui = d.api.ui
	_buttons([["Start overhead", func() -> void: d.start_timelapse(false)],
		["Start in the background", func() -> void: d.start_timelapse(true)], ["Stop", Callable(d, "stop_timelapse")]])
	_live_label(func() -> String: return d.timelapse.label() if d.timelapse_running() else "Not running. Overhead: the camera goes up and you play on through it. In the background: your camera stays with you and a second one films the area.")
	_add(ui.row("A frame every", _slider("timelapse_every", 0.0, 60.0, 0.5, "%s s")))
	_add(ui.row("Height", _slider("timelapse_height", 30.0, 600.0, 5.0, "%s tiles")))
	_add(ui.row("Looking", ui.dropdown([["Straight down", "down"], ["At Factorio's angle", "factorio"]], d.options["timelapse_angle"], _setter("timelapse_angle"))))
	_add(ui.row("Time of day", ui.dropdown(DAYTIMES, d.options["timelapse_daytime"], _setter("timelapse_daytime"))))
	_add(ui.row("Background frames", ui.dropdown(WIDTHS, d.options["timelapse_width"], _setter("timelapse_width"))))
	_add(_check("Orthographic (no perspective)", "timelapse_ortho"))
	_add(_check("Ask Zenith for lighter updates while it runs", "timelapse_lighter"))
	_add(_check("Hide the interface for frames on screen", "timelapse_clean"))
	_buttons([["Open the frames folder", _open_frames]])


func _follow_tab() -> void:
	var ui = d.api.ui
	_buttons([["Anything", func() -> void: d.start_tracking()], ["A train", func() -> void: d.start_tracking("train")],
		["A vehicle", func() -> void: d.start_tracking("vehicle")], ["A player", func() -> void: d.start_tracking("player")]])
	_buttons([["A robot", func() -> void: d.start_tracking("robot")], ["A rocket or pod", func() -> void: d.start_tracking("rocket")],
		["Biters", func() -> void: d.start_tracking("biters")], ["The next one", func() -> void: d.tracking.next_target()]])
	var places: Array = [["Behind", "behind"], ["Beside", "beside"], ["Above", "above"], ["From a fixed spot", "fixed"], ["Riding along", "ride"]]
	var place := func(v) -> void: d.tracking.set_placement(str(v))
	_add(ui.row("From", ui.dropdown(places, d.options["placement"], place)))
	_add(ui.note("Follows the nearest to the middle of the picture. %s follows what moves there, %s the next one of the same kind, %s changes where the camera rides." % [
		d.api.keys.text("track"), d.api.keys.text("next"), d.api.keys.text("placement")], 500))


func _moves_tab() -> void:
	var ui = d.api.ui
	var kinds: Array = Moves.KINDS.map(func(k: String) -> Array: return [Moves.NAMES[k], k])
	_add(ui.row("Move", ui.dropdown(kinds, d.options["move_kind"], _setter("move_kind"))))
	_add(ui.row("Speed", _slider("move_speed", 1.0, 40.0, 0.5, "%s tiles/s")))
	_add(ui.row("Length", _slider("move_length", 10.0, 400.0, 5.0, "%s tiles")))
	_add(_check("Loop (an orbit goes on round, the others there and back)", "move_loop"))
	_buttons([["Start", func() -> void: d.start_move()], ["Stop", func() -> void: d.stop()]])
	_add(ui.note("Moves go round the ground in the middle of the picture. An orbit's length is in sixths of a turn per 10 (60: one turn) and its speed in 1.5° a second per step.", 500))


func _path_tab() -> void:
	var ui = d.api.ui
	var name_box: LineEdit = ui.textbox(d.path.name, "Path name")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ui.kit.px(8))
	row.add_child(name_box)
	var make := func() -> void:
		d.new_path(name_box.text)
		_open("Path")
	row.add_child(ui.button("New path", make))
	_add(ui.row("Path", row))
	if not d.saved_paths.is_empty():
		var names: Array = d.saved_paths.keys().map(func(n: String) -> Array: return [n, n])
		var pick := func(v) -> void:
			d.load_path(str(v))
			_open("Path")
		_add(ui.row("Saved paths", ui.dropdown(names, d.path.name, pick)))
	_live_label(func() -> String: return "%d points in \"%s\"" % [d.path.points.size(), d.path.name])
	var remove_last := func() -> void:
		d.path.remove_last()
		d.save_paths()
		refresh()
	var clear := func() -> void:
		d.path.clear()
		d.save_paths()
		refresh()
	_buttons([["Add a point here", Callable(d, "add_path_point")], ["Remove the last", remove_last], ["Clear", clear]])
	_add(ui.row("Speed", _slider("path_speed", 1.0, 60.0, 0.5, "%s tiles/s")))
	_add(_check("Loop (round and round, three points or more)", "path_loop"))
	_buttons([["Play", Callable(d, "play_path")], ["Stop", func() -> void: d.stop()]])
	_add(ui.note("Fly the free camera to each spot and press %s: each point keeps where the camera is, where it looks and its field of view. Paths are saved with this save." % d.api.keys.text("add_point"), 500))


func _idle_tab() -> void:
	var ui = d.api.ui
	_buttons([["Start idle mode", func() -> void: d.start_idle(false)], ["Stop", func() -> void: d.stop()]])
	_add(ui.row("Start by itself after", _slider("idle_after", 0.0, 30.0, 1.0, "%s min")))
	_add(ui.row("Each shot", _slider("idle_shot", 8.0, 90.0, 1.0, "%s s")))
	_add(ui.note("Idle mode picks something worth watching: a rocket launch, a fight, a train leaving a station, trains, vehicles and players on the move, robots, a busy corner of the base. Started by itself (0 min: never), any key or the mouse ends it.", 500))


func _shot_tab() -> void:
	var ui = d.api.ui
	_add(ui.row("Field of view", _slider("fov", 15.0, 100.0, 1.0, "%s°")))
	_add(_check("Depth of field (focused on what is filmed)", "dof"))
	_add(ui.row("Blur", _slider("dof_amount", 0.05, 1.0, 0.05, "%s")))
	_add(_check("Letterbox bars (2.39:1) while filming", "letterbox"))
	_add(ui.row("Lowest height", _slider("min_height", 0.5, 20.0, 0.5, "%s tiles")))
	_add(ui.row("Highest", _slider("max_height", 40.0, 800.0, 10.0, "%s tiles")))
	_add(ui.row("Tilt down at most", _slider("max_tilt_down", 10.0, 89.0, 1.0, "%s°")))
	_add(ui.row("Tilt up at most", _slider("max_tilt_up", 0.0, 89.0, 1.0, "%s°")))
	_buttons([["Hide the interface", Callable(d, "toggle_interface")]])


## Options in Zenith's Mods window (outside a game too).
func build_options(box: VBoxContainer) -> void:
	var ui = d.api.ui
	box.add_child(ui.note("In a game, %s opens the camera window and %s starts the free camera. Keys: Settings → Controls." % [d.api.keys.text("window"), d.api.keys.text("free_camera")], 480))
	box.add_child(ui.row("Start idle mode after", _slider("idle_after", 0.0, 30.0, 1.0, "%s min")))
	box.add_child(_check("Glide back to my camera at the end", "glide_back"))
	var folder: LineEdit = ui.textbox(str(d.options["frames_folder"]), "Default: " + ProjectSettings.globalize_path(d.api.storage.folder().path_join("frames")))
	folder.custom_minimum_size.x = ui.kit.px(420)
	folder.text_submitted.connect(func(t: String) -> void:
		d.options["frames_folder"] = t.strip_edges()
		d.options_changed())
	folder.focus_exited.connect(func() -> void:
		d.options["frames_folder"] = folder.text.strip_edges()
		d.options_changed())
	box.add_child(ui.row("Timelapse frames", folder))


# --- helpers ------------------------------------------------------------------------------------

func _add(c: Control) -> void:
	_content.add_child(c)


func _buttons(list: Array) -> void:
	var ui = d.api.ui
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ui.kit.px(6))
	for pair in list:
		var b: Button = ui.button(str(pair[0]), pair[1])
		b.custom_minimum_size.x = ui.kit.px(118)
		row.add_child(b)
	_add(row)


func _live_label(text: Callable) -> void:
	var l: Label = d.api.ui.note("", 500)
	_add(l)
	_live.append([l, text])


func _setter(key: String) -> Callable:
	return func(v) -> void:
		d.options[key] = v
		d.options_changed()


func _check(text: String, key: String) -> CheckBox:
	var changed := func(on: bool) -> void:
		d.options[key] = on
		d.options_changed()
	return d.api.ui.checkbox(text, bool(d.options[key]), changed)


func _slider(key: String, from: float, to: float, step: float, fmt: String) -> HBoxContainer:
	var changed := func(v: float) -> void:
		d.options[key] = v
		d.options_changed()
	var s: Dictionary = d.api.ui.slider(from, to, step, float(d.options[key]), changed, fmt)
	return s["row"]


## A slider over a list's indices, showing the list's value.
func _index_slider(key: String, values: Array, unit: String) -> HBoxContainer:
	var ui = d.api.ui
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ui.kit.px(8))
	var s: HSlider = ui.menu_kit.slider(0, values.size() - 1, 1, int(d.options[key]))
	s.custom_minimum_size.x = ui.kit.px(160)
	var shown: Label = ui.label(_num(values[int(d.options[key])]) + unit)
	s.value_changed.connect(func(v: float) -> void:
		d.options[key] = int(v)
		shown.text = _num(values[int(v)]) + unit
		d.options_changed())
	row.add_child(s)
	row.add_child(shown)
	return row


func _orbit_here() -> void:
	if d.mode != d.free_cam:
		d.start_free()
	if d.mode == d.free_cam and not d.free_cam.orbiting:
		d.free_cam.toggle_orbit()


func _open_frames() -> void:
	var folder: String = d.timelapse.folder
	if folder == "":
		folder = str(d.options["frames_folder"]) if str(d.options["frames_folder"]) != "" else d.api.storage.folder().path_join("frames")
	var path := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(path)
	OS.shell_open(path)


static func _num(v) -> String:
	return str(int(v)) if float(v) == floorf(float(v)) else str(v)
