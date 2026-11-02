# Zenith Cinematic Camera

A camera add-on for [Zenith](https://github.com/unjustodin/Zenith), the 3D view for Factorio:
free-flying shots, smooth camera moves, tracking shots, overhead timelapses and a recorder camera
that films your factory from an angle while you play, for screenshots, YouTube videos and just
watching your base run.

Nothing it does changes the game: it only moves Zenith's camera and changes what is shown.

## What it does

- **Free camera.** Fly anywhere, away from your character, at a fixed speed you change with
  <kbd>+</kbd> and <kbd>−</kbd>; look with the mouse, zoom with the wheel. Every move eases in and
  out, so nothing starts or stops with a jolt. <kbd>O</kbd> orbits slowly round the point in the
  middle of the screen; <kbd>+</kbd> and <kbd>−</kbd> then change the orbit's speed.
- **Hide the interface and the cursor** in one key, for a clean picture.
- **Overhead timelapse.** A fixed shot high above an area, straight down or at Factorio's angle,
  left running while you play. It saves a frame every few seconds (numbered PNGs, ready to join
  into a video), can ask Zenith for lighter updates so a long recording costs the game less, and
  can hold the time of day or let night fall. On screen (you play on through it) or in the
  background (your own camera stays with you and a second camera films the area).
- **Tracking shots.** Follow a train, a car or tank, a spidertron, a player, a robot, a rocket or
  cargo pod, or a group of biters: from behind, beside, above, from a fixed spot that turns to
  watch, or **riding along** on the front of a train or a car. <kbd>N</kbd> switches to the next
  one of the same kind.
- **Preset moves.** Orbit, fly-over, dolly, crane, push in and pull out round the middle of the
  picture, each with a speed and a length, once or looping.
- **Paths and keyframes.** Fly to a spot, press <kbd>K</kbd> to drop a point (the camera's place,
  direction and field of view), and again elsewhere; <kbd>P</kbd> glides through them on a smooth
  curve, easing in and out. Paths are saved with the save, so a shot can be repeated after the base
  has grown.
- **Idle mode.** The camera picks something interesting and films it for a while, then moves on:
  a rocket launch, a fight at the walls, a train leaving a station, vehicles and players on the
  move, robots, a busy corner of the base. On demand, or by itself after some minutes without
  input. Good for a second monitor or a stream's break screen.
- **Clean shots.** Field of view, depth of field focused on what is filmed, the camera's height
  and tilt limits, and letterbox bars for a film look.
- **Camera mode and the recorder.** A camera circling above you (or another player, or a spot)
  that records video or frames while you play. See below.

When a shot ends, the camera glides back to your own view.

## Camera mode and recording

<kbd>Alt</kbd>+<kbd>F8</kbd> switches to camera mode: Zenith's view becomes the recorder's shot,
and a panel docked on the left has every control:

- **Follow** a player (you, or another player from the list) or **stay on a spot** (the ground in
  the middle of the picture), at a **distance** and **tilt**, circling at the **spin speed**
  (0 holds still).
- **Combat zoom**: when a fight starts near what is filmed (enemies attacking, turrets firing:
  Zenith's fight events), the camera glides there, closer (its own distance), and circles slowly
  above it; when the fight has been quiet for 10 seconds it glides back to the other shot.
- **Periodic angle swaps**: every N seconds a new angle round and down, glided to.
- **Timelapse**: a frame every N seconds instead of a video's frame rate (the video plays at 24,
  30 or 60 frames a second).
- **Recording**: as a video (`.avi`, Motion-JPEG, which VLC, mpv, ffmpeg and most editors open),
  or as numbered PNG or JPEG images; 720p, 1080p, 1440p, 2160p or the window's size; 10 to 60
  frames a second. **Record** starts and stops it (or <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F8</kbd>).

Then either:

- **leave Zenith on the camera view and play in Factorio's own window** (Zenith's game menu, or
  Ctrl+F9, brings it up). Keep Zenith's window open behind it, not minimised: a minimised window
  draws nothing. While recording, Zenith isn't minimised when it loses focus (Zenith 1.1's add-on
  API), and its frame-rate cap stays at the recording's rate; or
- **close the camera view** (its × or *Close the camera view*, Esc, or Alt+F8 again) and play in
  Zenith as usual: the recorder keeps filming in the background from its own camera. A red dot,
  the time and a Stop button show at the top while it records (not in the recording).

In the background only what Zenith has loaded round you is drawn, and Zenith fits the sun's
shadows to your own view: the further the recorder looks from where you are, the fainter its
shadows (they are whole while the camera view is shown, and close to whole following yourself).

What it costs, measured roughly on the laptop it was written on (an RTX 5060 laptop GPU, a 1600 ×
900 window, vsync off, against Zenith's mock server; other work shared the laptop, so the numbers
move by a millisecond or so). Average frame time, recording in the background:

| | Frame time | Added |
|---|---|---|
| Not recording | 5.6 ms | |
| Video 1080p, 30 frames a second | 6.7 ms | +1.1 ms |
| The same, reading frames back the waiting way (before) | 9.9 ms | +4.2 ms |
| JPEG images 1080p, 30 a second | 7.1 ms | +1.5 ms |
| PNG images 1080p, 30 a second | 7.0 ms | +1.4 ms, but about 70% of frames skipped |
| Video 720p, 30 a second | 6.6 ms | +0.9 ms |
| Video 1080p, 15 a second | 6.1 ms | +0.5 ms |
| Timelapse, a PNG every 2 s | 5.8 ms | +0.2 ms |

The recorder's view is drawn only when a frame is due and copied back from the graphics card
without waiting for it (`RenderingDevice.texture_get_data_async`); encoding runs on worker
threads. Video at 1080p is about 0.6 MB a frame (18 MB a second at 30 frames a second). PNG
frames are about 3 MB and too slow to encode at 30 a second (the panel counts the frames
skipped): use the video, JPEG, 720p or a lower rate, or PNG for timelapses. Zenith kept recording
at full rate with another window in front of it; minimised, it drew almost nothing (14 frames in
3 seconds instead of 90).

## Making the zip

`python make_zip.py` writes `dist/cinematic-camera_<version>.zip` (the version from `addon.json`),
holding a `cinematic-camera/` folder. Zenith loads that zip as it is from its add-ons folder; no
unpacking.

## Installing

You need Zenith with add-on support (add-on API 1, which this add-on asks for in its
`addon.json`; a Zenith without it says the add-on needs a newer Zenith). With API 1.1 its
settings are on its page of Zenith's **Add-ons** menu, with its keys, and recording keeps Zenith
drawing while its window is behind Factorio's.

1. Put `cinematic-camera_<version>.zip` (or this folder, the one with `addon.json` in it) in
   Zenith's add-ons folder:
   `%APPDATA%\Godot\app_userdata\Zenith\addons\` on Windows,
   `~/.local/share/godot/app_userdata/Zenith/addons/` on Linux, or an `addons` folder beside
   `Zenith.exe`.
2. Start Zenith. The **Add-ons** menu (main menu, Esc menu, Settings) lists *Cinematic camera*,
   switched on; its page has every setting and key.

To try a copy you're working on: `Zenith.exe -- --addons=C:/path/to/camera-add-on` (or
`godot --path client -- --addons=...` from Zenith's project).

## Keys

All of them can be changed on the add-on's page of Zenith's **Add-ons** menu, or in **Settings →
Controls** under *Cinematic camera*.

| Key | |
|---|---|
| <kbd>F8</kbd> | Free camera on and off; ends any shot and glides back to your view |
| <kbd>Shift</kbd>+<kbd>F8</kbd> | The camera window: timelapse, tracking, moves, paths, idle mode and shot options |
| <kbd>F11</kbd> | Hide the interface and the cursor, and show them again |
| <kbd>Ctrl</kbd>+<kbd>F8</kbd> | Idle mode on and off |
| <kbd>Alt</kbd>+<kbd>F8</kbd> | Camera mode (the recorder's view and its panel) on and off |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>F8</kbd> | Start and stop recording |

While the add-on has the camera (your own character stands still meanwhile):

| Key | |
|---|---|
| <kbd>W</kbd> <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> or the arrows | Fly |
| <kbd>E</kbd> or <kbd>Space</kbd> / <kbd>Q</kbd> or <kbd>Ctrl</kbd> | Up / down |
| Mouse, wheel | Look, zoom (the field of view) |
| <kbd>+</kbd> / <kbd>−</kbd> | Faster / slower (while orbiting: the orbit's speed) |
| <kbd>O</kbd> | Orbit the middle of the screen, and stop |
| <kbd>T</kbd> | Follow what moves in the middle of the screen |
| <kbd>N</kbd> | Follow the next one of the same kind |
| <kbd>V</kbd> | Follow from behind, beside, above, a fixed spot, or ride along |
| <kbd>K</kbd> | Add a path point where the camera is |
| <kbd>P</kbd> | Play the path, and stop it |
| <kbd>B</kbd> | Letterbox bars on and off |

Esc opens Zenith's menu as usual (and closes the camera window first).

## Where things are kept

- Options (speeds, the shot options, the timelapse and recording settings) for every save: in
  Zenith's settings file (section `addon_cinematic_camera`) with add-on API 1.1, and
  `user://addons-data/cinematic-camera/options.json` in Zenith's user data.
- Recordings: `user://addons-data/cinematic-camera/recordings/<save>/<date and time>/`, or a
  folder set on the add-on's page (*Recordings folder*). The panel's *Open the recordings folder*
  opens it. Turn a video into a small MP4 with
  `ffmpeg -i recording.avi -c:v libx264 -pix_fmt yuv420p recording.mp4`.
- Paths, with each save: `user://addons-data/cinematic-camera/saves/<save>/paths.json`.
- Timelapse frames: `user://addons-data/cinematic-camera/frames/<save>/<date and time>/`, or a
  folder set in the Mods window's Options. The camera window's *Open the frames folder* opens it.
  Join them with any video tool, for example
  `ffmpeg -framerate 30 -i frame_%05d.png -pix_fmt yuv420p timelapse.mp4`.

Sound isn't recorded (the add-on films the world only): add it with OBS or in an editor.

## Licence

MIT ([LICENSE](LICENSE)).

This is an unofficial fan project. "Factorio" is a trademark of Wube Software; this project is
not made, endorsed or supported by Wube.
