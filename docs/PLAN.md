# Plan

The add-on is planned, not built. This page says what it should do, what it needs from Zenith,
and the order to build it in.

## Background

Zenith shows a running Factorio game in 3D: Factorio runs the game unchanged, a small bridge mod
streams the world to the Zenith client, and the client draws it. The client already has three
cameras of its own: the angled view that follows your character, Factorio's own view (F6) and
first person (F5). This add-on adds cameras for filming and watching.

People asked for these when Zenith was first shown: following a random train on a wall-mounted
monitor, watching a biter attack from a safe spot, riding the front of a train through the base,
and being able to turn the camera freely.

## Features

### Free camera

- Toggle with a key (F8 by default). The character stays where it is; the camera detaches.
- Move with WASD (and Q/E or Space/Ctrl for up and down), look with the mouse.
- A fixed speed, changed with <kbd>+</kbd> and <kbd>−</kbd>, so moves look smooth on video
  instead of following the mouse's jitter.
- <kbd>O</kbd> starts a slow orbit round the point in the middle of the screen; <kbd>+</kbd> and
  <kbd>−</kbd> then change the orbit's speed.
- Smoothing on every move: acceleration and easing, no instant starts or stops.

### Overhead timelapse

- A fixed camera high over an area you pick, looking straight down or at Factorio's angle,
  left running while you play.
- Optional lower update rate for things that move, so a long recording costs the game less.
  Zenith's bridge already has settings for how often and how far it sends moving things; the
  add-on would ask for a lighter set while the timelapse runs.
- A frame-capture mode that saves an image every N seconds, ready to join into a timelapse, as
  well as plain screen recording.
- Lock the time of day, or let night fall for a day-night timelapse.

### Preset moves

- Orbit, fly-over, dolly (a straight line), crane (straight up or down), push in and pull out.
- Each with a speed and a length, and loopable.

### Paths and keyframes

- Place points: each stores the camera's position, direction and field of view.
- The camera glides through them on a smooth curve, with easing in and out.
- Save paths with the save and reuse them, so a shot can be repeated after changes to the base.

### Tracking

- Follow a moving thing: a train (or one wagon), a car, a spidertron, a player, a robot, a rocket
  or cargo pod, a group of biters.
- Placement: behind, beside, above, or from a fixed spot that turns to watch.
- Ride-along: the camera on the front of a train or a car.
- Switch to the next train or the next player with a key.

### Idle mode

- After a while with no input, or on demand, the camera picks something interesting and films
  it for a while, then moves on: a train leaving a station, a rocket launch, a fight at the walls,
  a busy belt line, a platform leaving orbit.
- Meant for a second monitor or a stream's break screen.

### Clean shots

- Hide the interface and the cursor in one key.
- Field of view, depth of field (focus on what's tracked), and the camera's height and tilt limits.
- Letterbox bars for a film look, if wanted.

## What it needs from Zenith

Zenith has no add-on support yet. This add-on is the test case for designing it. It needs:

1. **Taking over the camera:** the add-on can own the camera, and hand it back to the player's
   camera cleanly.
2. **Keys:** its own key bindings, shown and rebindable in Zenith's Controls settings.
3. **A settings panel:** a small window in Zenith's style for paths, presets and options.
4. **The world, read-only:** where trains, players, vehicles, rockets and biters are, from the
   client's own copy of the world. Nothing the add-on does changes the game.
5. **Events:** a train leaving a stop, a rocket launching, a fight starting, for idle mode.
6. **Lighter updates:** a way to ask the bridge for slower or smaller updates while a timelapse
   runs.
7. **Hiding the interface and saving frames.**
8. **Saving its own data** (paths, presets) next to the save.

## How it would be installed

Not decided yet; it depends on how Zenith loads add-ons. The simplest option is a folder dropped
into Zenith's add-ons folder. The add-on will say which Zenith version it needs, so an update to
Zenith can't silently break it.

## Order of work

1. Zenith: the camera, keys and settings hooks (1-3 above).
2. Free camera with fixed speed and orbit.
3. Overhead timelapse, then frame capture and lighter updates.
4. Tracking and ride-along.
5. Preset moves, then paths and keyframes.
6. Idle mode.
7. Clean-shot options.

## Not planned

- Anything that changes the game. This add-on only moves the camera and changes what's shown.
- Recording video itself: use OBS or similar. Frame capture for timelapses is the exception.
