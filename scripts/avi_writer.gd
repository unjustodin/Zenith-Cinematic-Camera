extends RefCounted
## A Motion-JPEG .avi file written frame by frame (AVI 1.0: RIFF 'AVI ', a 'movi' list of '00dc'
## JPEG chunks, an 'idx1' index), the same container Godot's own movie writer makes. Godot's movie
## writer can only film the whole window at a fixed rate from the start of the program, so the
## recorder writes its own file from its off-screen camera instead. Plays in VLC, mpv, ffmpeg,
## browsers' and most editors' importers; convert with
## `ffmpeg -i rec.avi -c:v libx264 -pix_fmt yuv420p rec.mp4` for a small file.
##
## A file is closed and the next one started past LIMIT bytes (AVI 1.0's offsets are 32-bit and
## many players stop at 1-2 GB): rec.avi, rec_2.avi, rec_3.avi...

const LIMIT := 1000 * 1000 * 1000
const AVIF_HASINDEX := 0x10
const AVIIF_KEYFRAME := 0x10

var path := ""
var width := 0
var height := 0
var fps := 30
var frames := 0  # in the file open now
var total_frames := 0
var parts: Array[String] = []

var _f: FileAccess
var _movi_at := 0  # where the 'movi' list's fourcc is (the index counts from there)
var _index := PackedInt32Array()  # offset, size pairs
var _biggest := 0
var _base := ""


## Opens the first file. False when it can't be written.
func open(file_path: String, w: int, h: int, rate: int) -> bool:
	_base = file_path.get_basename()
	width = w
	height = h
	fps = maxi(rate, 1)
	return _start(file_path)


func _start(file_path: String) -> bool:
	path = file_path
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	_f = FileAccess.open(file_path, FileAccess.WRITE)
	if _f == null:
		return false
	parts.append(file_path)
	frames = 0
	_biggest = 0
	_index = PackedInt32Array()
	_f.store_buffer("RIFF".to_ascii_buffer())
	_f.store_32(0)  # the whole file's size, written on close
	_f.store_buffer("AVI ".to_ascii_buffer())
	# hdrl: avih (56) + strl list (4 + strh 8+56 + strf 8+40)
	var strl_size := 4 + (8 + 56) + (8 + 40)
	var hdrl_size := 4 + (8 + 56) + (8 + strl_size)
	_list("hdrl", hdrl_size)
	_chunk("avih", 56)
	_f.store_32(int(1000000.0 / fps))  # microseconds a frame
	_f.store_32(0)  # max bytes a second (patched)
	_f.store_32(0)
	_f.store_32(AVIF_HASINDEX)
	_f.store_32(0)  # frames (patched)
	_f.store_32(0)
	_f.store_32(1)  # streams
	_f.store_32(0)  # suggested buffer (patched)
	_f.store_32(width)
	_f.store_32(height)
	for i in 4:
		_f.store_32(0)
	_list("strl", strl_size)
	_chunk("strh", 56)
	_f.store_buffer("vids".to_ascii_buffer())
	_f.store_buffer("MJPG".to_ascii_buffer())
	_f.store_32(0)  # flags
	_f.store_16(0)  # priority
	_f.store_16(0)  # language
	_f.store_32(0)  # initial frames
	_f.store_32(1)  # scale
	_f.store_32(fps)  # rate: fps frames a second
	_f.store_32(0)  # start
	_f.store_32(0)  # length in frames (patched)
	_f.store_32(0)  # suggested buffer (patched)
	_f.store_32(0xFFFFFFFF)  # quality: default
	_f.store_32(0)  # sample size: frames vary
	_f.store_16(0)
	_f.store_16(0)
	_f.store_16(width)
	_f.store_16(height)
	_chunk("strf", 40)
	_f.store_32(40)
	_f.store_32(width)
	_f.store_32(height)
	_f.store_16(1)  # planes
	_f.store_16(24)  # bits a pixel
	_f.store_buffer("MJPG".to_ascii_buffer())
	_f.store_32(width * height * 3)
	for i in 4:
		_f.store_32(0)
	_f.store_buffer("LIST".to_ascii_buffer())
	_f.store_32(0)  # the movi list's size (patched)
	_movi_at = _f.get_position()
	_f.store_buffer("movi".to_ascii_buffer())
	return true


## Appends one frame (a JPEG file's bytes). False when the file can't take it.
func add(jpeg: PackedByteArray) -> bool:
	if _f == null:
		return false
	if _f.get_position() + jpeg.size() + 16 * (frames + 2) > LIMIT:
		_finish()
		if not _start("%s_%d.avi" % [_base, parts.size() + 1]):
			return false
	var at := _f.get_position()
	_f.store_buffer("00dc".to_ascii_buffer())
	_f.store_32(jpeg.size())
	_f.store_buffer(jpeg)
	if jpeg.size() % 2 == 1:
		_f.store_8(0)
	_index.append(at - _movi_at)
	_index.append(jpeg.size())
	_biggest = maxi(_biggest, jpeg.size())
	frames += 1
	total_frames += 1
	return true


## Writes the index and the sizes, and closes the file.
func close() -> void:
	_finish()


func _finish() -> void:
	if _f == null:
		return
	var movi_end := _f.get_position()
	_f.store_buffer("idx1".to_ascii_buffer())
	_f.store_32(frames * 16)
	for i in frames:
		_f.store_buffer("00dc".to_ascii_buffer())
		_f.store_32(AVIIF_KEYFRAME)
		_f.store_32(_index[i * 2])
		_f.store_32(_index[i * 2 + 1])
	var end := _f.get_position()
	_f.seek(4)
	_f.store_32(end - 8)
	_f.seek(_movi_at - 4)
	_f.store_32(movi_end - _movi_at)
	# avih: offsets from the start: RIFF(12) LIST hdrl(12) avih header(8) = 32
	_f.seek(32 + 4)
	_f.store_32(_biggest * fps)
	_f.seek(32 + 16)
	_f.store_32(frames)
	_f.seek(32 + 28)
	_f.store_32(_biggest + 8)
	# strh: avih ends at 32 + 56 = 88; LIST strl (12) and the strh header (8): its fields from 108
	_f.seek(108 + 32)
	_f.store_32(frames)
	_f.seek(108 + 36)
	_f.store_32(_biggest + 8)
	_f.close()
	_f = null


func _list(kind: String, size: int) -> void:
	_f.store_buffer("LIST".to_ascii_buffer())
	_f.store_32(size)
	_f.store_buffer(kind.to_ascii_buffer())


func _chunk(kind: String, size: int) -> void:
	_f.store_buffer(kind.to_ascii_buffer())
	_f.store_32(size)
