extends RefCounted
## The add-on's options as Zenith settings (add-on API 1.1: api.settings), so they show on its page
## of Zenith's Add-ons menu with its keys: [option, type, label, options]. The defaults are the
## director's DEFAULTS (main.gd). On a Zenith with API 1.0 the options are only in the add-on's own
## windows (and options.json).

const FreeCamera := preload("free_camera.gd")
const Moves := preload("moves.gd")
const Recorder := preload("recorder.gd")

const DAYTIMES := [["Let it run", "run"], ["Hold at noon", "0.0"], ["Hold at evening", "0.2"],
	["Hold at night", "0.5"], ["Hold at morning", "0.8"]]
const WIDTHS := [["The window's size", 0], ["1280 wide", 1280], ["1920 wide", 1920], ["2560 wide", 2560], ["3840 wide", 3840]]
const PLAY_RATES := [["24 frames a second", 24], ["30 frames a second", 30], ["60 frames a second", 60]]


static func entries() -> Array:
	var speeds: Array = []
	for i in FreeCamera.SPEEDS.size():
		speeds.append(["%s tiles/s" % _num(FreeCamera.SPEEDS[i]), i])
	var orbits: Array = []
	for i in FreeCamera.ORBIT_SPEEDS.size():
		orbits.append(["%s°/s" % _num(FreeCamera.ORBIT_SPEEDS[i]), i])
	var kinds: Array = Moves.KINDS.map(func(k: String) -> Array: return [Moves.NAMES[k], k])
	var cm := "Camera mode and recording"
	return [
		["rec_follow", "choice", "Follow", {"section": cm, "choices": [["A player", "player"], ["Stay on a spot", "spot"]]}],
		["rec_player", "text", "Player to follow (empty: you)", {"section": cm, "placeholder": "you"}],
		["rec_distance", "number", "Distance", {"section": cm, "min": 10.0, "max": 300.0, "step": 1.0, "unit": "tiles"}],
		["rec_tilt", "number", "Tilt", {"section": cm, "min": 15.0, "max": 89.0, "step": 1.0, "unit": "°"}],
		["rec_spin", "number", "Spin speed", {"section": cm, "min": 0.0, "max": 30.0, "step": 0.5, "unit": "°/s"}],
		["rec_combat", "bool", "Combat zoom (circle fights close up)", {"section": cm}],
		["rec_combat_distance", "number", "Combat zoom distance", {"section": cm, "min": 8.0, "max": 120.0, "step": 1.0, "unit": "tiles"}],
		["rec_combat_spin", "number", "Combat zoom spin", {"section": cm, "min": 0.0, "max": 20.0, "step": 0.5, "unit": "°/s"}],
		["rec_swaps", "bool", "Periodic angle swaps", {"section": cm}],
		["rec_swap_every", "number", "A new angle every", {"section": cm, "min": 5.0, "max": 180.0, "step": 1.0, "unit": "s"}],
		["rec_timelapse", "bool", "Timelapse (a frame every few seconds)", {"section": cm}],
		["rec_every", "number", "Timelapse: a frame every", {"section": cm, "min": 0.5, "max": 60.0, "step": 0.5, "unit": "s"}],
		["rec_play_rate", "choice", "Timelapse video plays at", {"section": cm, "choices": PLAY_RATES}],
		["rec_format", "choice", "Record as", {"section": cm, "choices": Recorder.FORMATS}],
		["rec_height", "choice", "Resolution", {"section": cm, "choices": Recorder.RESOLUTIONS}],
		["rec_rate", "choice", "Frame rate", {"section": cm, "choices": Recorder.RATES}],
		["rec_folder", "text", "Recordings folder", {"section": cm, "placeholder": "Zenith's add-on data folder"}],
		["speed", "choice", "Free camera speed", {"section": "Free camera", "choices": speeds}],
		["orbit_speed", "choice", "Orbit speed", {"section": "Free camera", "choices": orbits}],
		["mouse_sensitivity", "number", "Mouse look", {"section": "Free camera", "min": 0.2, "max": 3.0, "step": 0.05, "unit": "×"}],
		["glide_back", "bool", "Glide back to my camera at the end", {"section": "Free camera"}],
		["idle_after", "number", "Idle mode by itself after", {"section": "Idle mode", "min": 0.0, "max": 30.0, "step": 1.0, "unit": "min", "note": "0: never"}],
		["idle_shot", "number", "Idle mode: each shot", {"section": "Idle mode", "min": 8.0, "max": 90.0, "step": 1.0, "unit": "s"}],
		["move_kind", "choice", "Preset move", {"section": "Moves and paths", "choices": kinds}],
		["move_speed", "number", "Move speed", {"section": "Moves and paths", "min": 1.0, "max": 40.0, "step": 0.5}],
		["move_length", "number", "Move length", {"section": "Moves and paths", "min": 10.0, "max": 400.0, "step": 5.0}],
		["move_loop", "bool", "Loop moves", {"section": "Moves and paths"}],
		["path_speed", "number", "Path speed", {"section": "Moves and paths", "min": 1.0, "max": 60.0, "step": 0.5, "unit": "tiles/s"}],
		["path_loop", "bool", "Loop paths", {"section": "Moves and paths"}],
		["timelapse_every", "number", "Overhead timelapse: a frame every", {"section": "Overhead timelapse", "min": 0.0, "max": 60.0, "step": 0.5, "unit": "s"}],
		["timelapse_height", "number", "Height", {"section": "Overhead timelapse", "min": 30.0, "max": 600.0, "step": 5.0, "unit": "tiles"}],
		["timelapse_angle", "choice", "Looking", {"section": "Overhead timelapse", "choices": [["Straight down", "down"], ["At Factorio's angle", "factorio"]]}],
		["timelapse_daytime", "choice", "Time of day", {"section": "Overhead timelapse", "choices": DAYTIMES}],
		["timelapse_width", "choice", "Background frames", {"section": "Overhead timelapse", "choices": WIDTHS}],
		["timelapse_ortho", "bool", "Orthographic", {"section": "Overhead timelapse"}],
		["timelapse_lighter", "bool", "Ask Zenith for lighter updates", {"section": "Overhead timelapse"}],
		["timelapse_clean", "bool", "Hide the interface for frames on screen", {"section": "Overhead timelapse"}],
		["frames_folder", "text", "Timelapse frames folder", {"section": "Overhead timelapse", "placeholder": "Zenith's add-on data folder"}],
		["fov", "number", "Field of view", {"section": "Shot", "min": 15.0, "max": 100.0, "step": 1.0, "unit": "°"}],
		["dof", "bool", "Depth of field", {"section": "Shot"}],
		["dof_amount", "number", "Blur", {"section": "Shot", "min": 0.05, "max": 1.0, "step": 0.05}],
		["letterbox", "bool", "Letterbox bars while filming", {"section": "Shot"}],
		["min_height", "number", "Lowest height", {"section": "Shot", "min": 0.5, "max": 20.0, "step": 0.5, "unit": "tiles"}],
		["max_height", "number", "Highest", {"section": "Shot", "min": 40.0, "max": 800.0, "step": 10.0, "unit": "tiles"}],
		["max_tilt_down", "number", "Tilt down at most", {"section": "Shot", "min": 10.0, "max": 89.0, "step": 1.0, "unit": "°"}],
		["max_tilt_up", "number", "Tilt up at most", {"section": "Shot", "min": 0.0, "max": 89.0, "step": 1.0, "unit": "°"}],
	]


static func _num(v) -> String:
	return str(int(v)) if float(v) == floorf(float(v)) else str(v)
