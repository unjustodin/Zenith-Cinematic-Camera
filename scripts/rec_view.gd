extends RefCounted
## The camera view: Zenith's own camera shows the camera mode's shot (rec_shot.gd), the one the
## recorder films. The player's controls stay on, so you can keep playing in Zenith underneath it,
## or in Factorio's own window while Zenith shows the shot. Closing it hands the camera back; the
## recorder keeps filming in the background.

const Smooth := preload("smooth.gd")

var d  # the director
var takes_input := false


func _init(director) -> void:
	d = director


func label() -> String:
	return "Camera view: " + d.rec_shot.label()


func start(_from: Smooth.Pose) -> void:
	pass


func stop() -> void:
	pass


func focus_point():
	return d.rec_shot.fight if d.rec_shot.fight != null else d.rec_shot.base_target()


## The shot itself is worked out once a frame by the director (the recorder needs it too).
func update(_delta: float) -> Smooth.Pose:
	return d.rec_shot.pose().copy()


func input(_event: InputEvent) -> bool:
	return false
