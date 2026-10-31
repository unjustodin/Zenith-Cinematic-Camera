# Zenith Cinematic Camera

A camera add-on for [Zenith](https://github.com/unjustodin/Zenith), the 3D view for Factorio:
free-flying shots, smooth camera moves, tracking shots and overhead timelapses of your factory,
for screenshots, YouTube videos and just watching your base run.

> **Planned, no code yet.** This repository holds the plan for now. The add-on needs Zenith's
> add-on support, which is still being designed, and Zenith's own code isn't published yet. Watch
> or star the repo to hear when it starts.

## What it will do

- **Free camera.** Fly anywhere, away from your character, at a fixed speed you change with
  <kbd>+</kbd> and <kbd>−</kbd>. Press <kbd>O</kbd> to orbit slowly round where you're looking.
- **Overhead timelapse.** A fixed shot high above the base that you leave running while you play,
  so you can record the whole factory growing. It can ask Zenith to update less often, to keep
  the game running smoothly over long sessions.
- **Preset moves.** Orbit, fly-over, dolly along a line, crane up or down: pick one, set the
  speed, and let it run.
- **Paths and keyframes.** Drop points around your base and the camera glides between them,
  turning and easing as it goes.
- **Tracking shots.** Lock onto something that moves (a train, a player, a spidertron, a biter
  wave) and follow it, from behind, from the side or from a fixed spot.
- **Ride-along.** Sit on the front of a train or a car and see your base go by.
- **Idle mode.** Leave it alone and it wanders between interesting things: trains, rocket
  launches, fights, busy belts. Good for a second monitor.
- **Clean shots.** Hide the interface, lock the time of day or let it run, and set the field of
  view and depth of field.

More detail, and what the add-on needs from Zenith, is in [docs/PLAN.md](docs/PLAN.md).

## Why an add-on

Zenith itself stays focused on playing. Everything here is about filming and watching, and none
of it changes the game, so it fits well as an add-on. It's also meant as the worked example for
Zenith's add-on support: whatever this add-on needs, other add-ons will need too.

## Requirements (once it exists)

- Factorio 2.1 (your own copy) and Zenith.
- The add-on runs inside Zenith, so it works wherever Zenith does.

## Licence

MIT ([LICENSE](LICENSE)).

This is an unofficial fan project. "Factorio" is a trademark of Wube Software; this project is
not made, endorsed or supported by Wube.
