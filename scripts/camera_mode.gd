extends RefCounted
## Camera mode's panel, docked on the left (Alt+F8 by default): every control of the camera mode's
## shot and the recorder, and the Record button. While it's open Zenith's camera shows the shot
## (the camera view); closing it (its ×, Esc, "Close the camera view" or Alt+F8 again) gives you
## your own camera back and leaves the recorder filming in the background.

const Recorder := preload("recorder.gd")
const SettingsTable := preload("settings_table.gd")

var d  # the director
var _win := {}
var _content: VBoxContainer
var _live: Array = []  # [Label, Callable returning its text]
var _record: Button
var _players_seen := ""
var _clock := 0.0


func _init(director) -> void:
	d = director


func is_open() -> bool:
	return not _win.is_empty() and d.api.ui.is_open(_win["frame"])


func open() -> void:
	_ensure()
	_build()
	d.api.ui.show(_win["frame"], true)
	_dock()


func close() -> void:
	if not _win.is_empty():
		d.api.ui.show(_win["frame"], false)


## Rebuilt when an option changes elsewhere (Zenith's Add-ons menu) or the players change.
func rebuild() -> void:
	if is_open():
		_build()


func tick(delta: float) -> void:
	if not is_open():
		return
	_clock += delta
	if _clock < 0.25:
		return
	_clock = 0.0
	_dock()
	for pair in _live:
		if is_instance_valid(pair[0]):
			(pair[0] as Label).text = (pair[1] as Callable).call()
	if _record != null:
		_record.text = "Stop recording" if d.recorder.recording else "Record"
	var names := ",".join(_player_names())
	if names != _players_seen:
		_build()


## On the left, under Zenith's top bar, as tall as the screen allows.
func _dock() -> void:
	var frame: Control = _win["frame"]
	frame.position = Vector2(d.api.ui.kit.px(8), d.api.ui.kit.px(64))


func _ensure() -> void:
	if not _win.is_empty():
		return
	_win = d.api.ui.window("Camera mode")
	var frame: Control = _win["frame"]
	frame.name = "CameraModePanel"
	var box: VBoxContainer = _win["box"]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var screen: Vector2 = d.api.view.screen_size()
	scroll.custom_minimum_size = Vector2(d.api.ui.kit.px(380), clampf(screen.y - d.api.ui.kit.px(150), d.api.ui.kit.px(300), d.api.ui.kit.px(820)))
	box.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", d.api.ui.kit.px(5))
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)


func _build() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_live.clear()
	var ui = d.api.ui
	_live_label(func() -> String: return d.rec_shot.label())
	_add(ui.heading("Shot"))
	_add(_row("Follow", _dropdown("rec_follow", [["A player", "player"], ["Stay on a spot", "spot"]], "cm-follow")))
	var players: Array = [["You", ""]]
	for n in _player_names():
		players.append([n, n])
	_players_seen = ",".join(_player_names())
	_add(_row("Player", _dropdown("rec_player", players, "cm-player")))
	var spot: Button = ui.button("Stay on the spot in the middle", func() -> void:
		d.rec_shot.set_spot_here()
		d.options["rec_follow"] = "spot"
		d.options_changed()
		_build())
	spot.name = "cm-spot"
	_add(spot)
	_add(_row("Distance", _slider("rec_distance", 10.0, 300.0, 1.0, "%s tiles", "cm-distance")))
	_add(_row("Tilt", _slider("rec_tilt", 15.0, 89.0, 1.0, "%s°", "cm-tilt")))
	_add(_row("Spin speed", _slider("rec_spin", 0.0, 30.0, 0.5, "%s°/s", "cm-spin")))
	_add(ui.heading("Options"))
	_add(_check("Combat zoom: circle fights close up", "rec_combat", "cm-combat"))
	_add(_row("  distance", _slider("rec_combat_distance", 8.0, 120.0, 1.0, "%s tiles", "cm-combat-distance")))
	_add(_row("  spin", _slider("rec_combat_spin", 0.0, 20.0, 0.5, "%s°/s", "cm-combat-spin")))
	_add(_check("Periodic angle swaps", "rec_swaps", "cm-swaps"))
	_add(_row("  every", _slider("rec_swap_every", 5.0, 180.0, 1.0, "%s s", "cm-swap-every")))
	_add(_check("Timelapse", "rec_timelapse", "cm-timelapse"))
	_add(_row("  a frame every", _slider("rec_every", 0.5, 60.0, 0.5, "%s s", "cm-every")))
	_add(_row("  plays at", _dropdown("rec_play_rate", SettingsTable.PLAY_RATES, "cm-play-rate")))
	_add(ui.heading("Recording"))
	_add(_row("Record as", _dropdown("rec_format", Recorder.FORMATS, "cm-format")))
	_add(_row("Resolution", _dropdown("rec_height", Recorder.RESOLUTIONS, "cm-resolution")))
	_add(_row("Frame rate", _dropdown("rec_rate", Recorder.RATES, "cm-rate")))
	_record = ui.button("Stop recording" if d.recorder.recording else "Record", func() -> void: d.toggle_recording())
	_record.name = "cm-record"
	_record.custom_minimum_size.x = ui.kit.px(200)
	_add(_record)
	_live_label(func() -> String: return d.recorder.label() + ("" if d.recorder.recording else "  (%s: start and stop)" % d.api.keys.text("record")))
	_add(ui.button("Open the recordings folder", Callable(d, "open_recordings")))
	var close_view: Button = ui.button("Close the camera view", func() -> void: d.close_camera_mode())
	close_view.name = "cm-close"
	close_view.tooltip_text = "Your own camera back; a recording goes on in the background"
	_add(close_view)
	_add(ui.note("Record, then either leave Zenith showing this view and play in Factorio's own window (keep Zenith's window open behind it, not minimised), or close the view and play in Zenith: the recorder films on in the background. In the background only what Zenith has loaded round you is drawn, so follow yourself or a spot nearby. %s opens this panel, %s starts and stops recording." % [
		d.api.keys.text("camera_mode"), d.api.keys.text("record")], 360))


func _player_names() -> Array:
	var out: Array = []
	for p: Dictionary in d.api.world.players():
		if not bool(p["me"]) and bool(p["connected"]):
			out.append(str(p["name"]))
	return out


# --- helpers ------------------------------------------------------------------------------------

func _add(c: Control) -> void:
	_content.add_child(c)


func _row(text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", d.api.ui.kit.px(6))
	var l: Label = d.api.ui.label(text)
	l.custom_minimum_size.x = d.api.ui.kit.px(110)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	h.add_child(control)
	return h


func _live_label(text: Callable) -> void:
	var l: Label = d.api.ui.note("", 360)
	_add(l)
	_live.append([l, text])
	l.text = text.call()


func _dropdown(key: String, items: Array, node_name: String) -> OptionButton:
	var o: OptionButton = d.api.ui.dropdown(items, d.options[key], func(v) -> void:
		d.options[key] = v
		d.options_changed())
	o.name = node_name
	o.custom_minimum_size.x = d.api.ui.kit.px(220)
	return o


func _check(text: String, key: String, node_name: String) -> CheckBox:
	var c: CheckBox = d.api.ui.checkbox(text, bool(d.options[key]), func(on: bool) -> void:
		d.options[key] = on
		d.options_changed())
	c.name = node_name
	return c


func _slider(key: String, from: float, to: float, step: float, fmt: String, node_name: String) -> HBoxContainer:
	var s: Dictionary = d.api.ui.slider(from, to, step, float(d.options[key]), func(v: float) -> void:
		d.options[key] = v
		d.options_changed(), fmt)
	(s["slider"] as HSlider).custom_minimum_size.x = d.api.ui.kit.px(150)
	(s["row"] as Control).name = node_name
	(s["slider"] as Control).name = "slider"
	return s["row"]
