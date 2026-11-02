extends RefCounted
## The recorder: films from its own camera into an off-screen viewport and saves what it sees, so
## you can play on (in Zenith, or in Factorio's own window with Zenith behind it) while it records.
## Where its camera is comes from the camera mode's shot (rec_shot.gd); the camera view shows the
## same shot on Zenith's screen, and closing the view leaves the recorder filming in the
## background.
##
## The viewport is drawn only when a frame is due (a frame every 1/rate seconds, or one every N
## seconds as a timelapse) and copied back from the graphics card without waiting for it
## (RenderingDevice.texture_get_data_async: the copy arrives a frame or two later; reading it at
## once with get_image() stalled the game 13-20 ms a frame at 1080p), then encoded on worker
## threads:
##   png   numbered PNG files (lossless, big, the slowest to encode)
##   jpg   numbered JPEG files (quality 90)
##   avi   one Motion-JPEG .avi (avi_writer.gd), which most players and editors open
## A frame that comes due while too many are still being encoded is skipped (counted as dropped),
## so a slow disk or CPU never piles up memory or stalls the game.

const AviWriter := preload("avi_writer.gd")

const FORMATS := [["PNG images", "png"], ["JPEG images", "jpg"], ["Video (.avi, Motion-JPEG)", "avi"]]
const RESOLUTIONS := [["720p (1280 × 720)", 720], ["1080p (1920 × 1080)", 1080], ["1440p (2560 × 1440)", 1440], ["2160p (3840 × 2160)", 2160], ["The window's size", 0]]
const RATES := [["10 frames a second", 10], ["15 frames a second", 15], ["24 frames a second", 24], ["30 frames a second", 30], ["60 frames a second", 60]]
const JPEG_QUALITY := 0.9
## Frames being encoded at most; more are dropped.
const MAX_PENDING := 12

var d  # the director
var recording := false
var folder := ""
var format := "png"
var frames := 0
var dropped := 0
var started_msec := 0
var size := Vector2i.ZERO
## Main-thread milliseconds spent reading frames back (the GPU copy), for the panel and measurements.
var readback_msec := 0.0
var readback_count := 0
## Copies asked of the graphics card and not back yet.
var in_flight := 0
## Read back without waiting (false: an older Zenith or a renderer without a RenderingDevice).
var async_readback := true

var _session := 0  # each recording's number: a copy arriving after it ended is left out

var _viewport: SubViewport
var _camera: Camera3D
var _next_due := 0.0
var _clock := 0.0
var _capturing := false
var _pending: Array = []  # [task id, frame number, {"bytes": PackedByteArray}] in frame order
var _avi: AviWriter


func _init(director) -> void:
	d = director


## Seconds recorded so far (wall clock).
func seconds() -> float:
	return (Time.get_ticks_msec() - started_msec) / 1000.0 if recording else 0.0


## A frame every this many seconds of real time.
func interval() -> float:
	if bool(d.options["rec_timelapse"]):
		return maxf(float(d.options["rec_every"]), 0.1)
	return 1.0 / maxf(float(d.options["rec_rate"]), 1.0)


func label() -> String:
	if not recording:
		return "Not recording"
	var t := int(seconds())
	var text := "● REC %d:%02d · %d frames" % [t / 60, t % 60, frames]
	if dropped > 0:
		text += " (%d skipped)" % dropped
	return text


## Starts recording into a new folder under the recordings folder.
func start() -> bool:
	if recording:
		return true
	if d.api.view.world_3d() == null:
		d.api.ui.message("Recording needs a game")
		return false
	format = str(d.options["rec_format"])
	folder = _new_folder()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	_make_viewport()
	if format == "avi":
		_avi = AviWriter.new()
		var rate := int(d.options["rec_play_rate"]) if bool(d.options["rec_timelapse"]) else int(d.options["rec_rate"])
		if not _avi.open(ProjectSettings.globalize_path(folder.path_join("recording.avi")), size.x, size.y, rate):
			d.api.ui.message("Can't write to %s" % ProjectSettings.globalize_path(folder))
			_free_viewport()
			_avi = null
			return false
	frames = 0
	dropped = 0
	in_flight = 0
	_session += 1
	readback_msec = 0.0
	readback_count = 0
	_clock = 0.0
	_next_due = 0.0
	started_msec = Time.get_ticks_msec()
	recording = true
	# Zenith keeps drawing while its window is behind Factorio's (API 1.1): not minimised on focus
	# loss, and its frame-rate cap no lower than the recording's rate.
	if d.api.get("level") != null and float(d.api.level) >= 1.1:
		d.api.view.keep_drawing(int(ceilf(1.0 / interval())) if not bool(d.options["rec_timelapse"]) else 1)
	d.api.ui.message("Recording to %s" % ProjectSettings.globalize_path(folder))
	d.api.note("recording %s %dx%d to %s" % [format, size.x, size.y, ProjectSettings.globalize_path(folder)])
	return true


## Stops: what is still being encoded is finished, the video closed.
func stop() -> void:
	if not recording:
		return
	recording = false
	_drain(true)
	if _avi != null:
		_avi.close()
		_avi = null
	_free_viewport()
	if d.api.get("level") != null and float(d.api.level) >= 1.1:
		d.api.view.keep_drawing(0)
	var where := ProjectSettings.globalize_path(folder)
	d.api.ui.message("Recorded %d frames to %s" % [frames, where])
	d.api.note("recorded %d frames (%d skipped), readback %.2f ms a frame, to %s" % [frames, dropped, readback_msec / maxf(readback_count, 1), where])


## Each frame while recording: the camera follows the shot; when a frame is due, the viewport is
## drawn this frame and read back after it.
func tick(delta: float, pose) -> void:
	if not recording:
		_drain(false)
		return
	_drain(false)
	if _camera != null and pose != null:
		_camera.global_transform = pose.transform()
		_camera.fov = pose.fov if pose.fov > 0.0 else float(d.options["fov"])
	_clock += delta
	if _capturing or _clock < _next_due:
		return
	var step := interval()
	_next_due += step
	if _next_due < _clock:
		_next_due = _clock + step  # far behind (a hitch, a slow machine): no burst of frames to catch up
	if _pending.size() + in_flight >= MAX_PENDING:
		dropped += 1
		return
	_capture()


func _capture() -> void:
	_capturing = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_capturing = false
	if not recording or _viewport == null:
		return
	var t0 := Time.get_ticks_usec()
	var rd := RenderingServer.get_rendering_device()
	var tex := RenderingServer.texture_get_rd_texture(_viewport.get_texture().get_rid()) if rd != null and async_readback else RID()
	if tex.is_valid():
		var fmt: RDTextureFormat = rd.texture_get_format(tex)
		var w := int(fmt.width)
		var h := int(fmt.height)
		var image_format := _image_format(fmt.format)
		if image_format >= 0:
			in_flight += 1
			var session := _session
			var err := rd.texture_get_data_async(tex, 0, func(data: PackedByteArray) -> void:
				if session != _session:
					return
				in_flight -= 1
				if not recording:
					return
				var img := Image.create_from_data(w, h, false, image_format, data)
				_encode(img))
			readback_msec += (Time.get_ticks_usec() - t0) / 1000.0
			readback_count += 1
			if err == OK:
				return
			in_flight -= 1
	# The waiting way: the copy is made now.
	var image := _viewport.get_texture().get_image()
	readback_msec += (Time.get_ticks_usec() - t0) / 1000.0
	readback_count += 1
	_encode(image)


## Image formats the viewport's texture comes in (8 bits a channel, or half floats with HDR).
static func _image_format(rd_format: int) -> int:
	match rd_format:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			return Image.FORMAT_RGBA8
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			return Image.FORMAT_RGBAH
	return -1


func _encode(image: Image) -> void:
	if image == null or image.is_empty():
		dropped += 1
		return
	frames += 1
	var n := frames
	var box := {}
	var kind := format
	var path := ProjectSettings.globalize_path(folder.path_join("frame_%06d.%s" % [n, kind]))
	var job := func() -> void:
		if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
			image.convert(Image.FORMAT_RGBA8)
		match kind:
			"png":
				image.save_png(path)
			"jpg":
				image.convert(Image.FORMAT_RGB8)
				image.save_jpg(path, JPEG_QUALITY)
			"avi":
				image.convert(Image.FORMAT_RGB8)
				box["bytes"] = image.save_jpg_to_buffer(JPEG_QUALITY)
	_pending.append([WorkerThreadPool.add_task(job, false, "recorder frame"), n, box])


## Frames encoded, in order: an .avi's are appended to it (the file is written in frame order).
## Copies still on their way from the graphics card when recording stops are left out.
func _drain(all: bool) -> void:
	while not _pending.is_empty():
		var p: Array = _pending[0]
		if not all and not WorkerThreadPool.is_task_completed(int(p[0])):
			return
		WorkerThreadPool.wait_for_task_completion(int(p[0]))
		_pending.pop_front()
		if _avi != null and (p[2] as Dictionary).has("bytes"):
			_avi.add(p[2]["bytes"])


func _make_viewport() -> void:
	_free_viewport()
	var screen: Vector2 = d.api.view.screen_size()
	var h := int(d.options["rec_height"])
	if h <= 0:
		size = Vector2i(screen)
	else:
		size = Vector2i(roundi(h * 16.0 / 9.0), h)
	size = Vector2i(maxi(size.x - size.x % 2, 64), maxi(size.y - size.y % 2, 64))
	_viewport = SubViewport.new()
	_viewport.name = "RecorderView"
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.world_3d = d.api.view.world_3d()
	# Drawn as Zenith's own view is: its anti-aliasing, level of detail and render scale.
	var main_vp: Viewport = d.get_viewport()
	_viewport.msaa_3d = main_vp.msaa_3d
	_viewport.screen_space_aa = main_vp.screen_space_aa
	_viewport.use_taa = main_vp.use_taa
	_viewport.mesh_lod_threshold = main_vp.mesh_lod_threshold
	# Always drawn at the recording's full size: Zenith's render scale (and FSR) is for the screen,
	# never copied onto the recording.
	_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_viewport.scaling_3d_scale = 1.0
	_viewport.fsr_sharpness = 0.0
	_viewport.positional_shadow_atlas_size = main_vp.positional_shadow_atlas_size
	_camera = Camera3D.new()
	_camera.far = 3000.0
	var main_cam: Camera3D = main_vp.get_camera_3d()
	if main_cam != null:
		_camera.keep_aspect = main_cam.keep_aspect  # the same field of view frames the same picture
		_camera.near = main_cam.near
		_camera.cull_mask = main_cam.cull_mask
	_viewport.add_child(_camera)
	_camera.current = true
	d.add_child(_viewport)


func _free_viewport() -> void:
	if _viewport != null:
		_viewport.queue_free()
	_viewport = null
	_camera = null
	_capturing = false


## What the recorder's camera saw last (null while not recording), for showing it on screen.
func texture() -> Texture2D:
	return _viewport.get_texture() if _viewport != null else null


func root_folder() -> String:
	var root := str(d.options["rec_folder"])
	return root if root != "" else d.api.storage.folder().path_join("recordings")


func _new_folder() -> String:
	var save: String = d.api.storage.save_key()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	return root_folder().path_join(save if save != "" else "game").path_join(stamp)
